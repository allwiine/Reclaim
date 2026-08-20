//
//  ScanCoordinator.swift
//  ReclaimAppCore
//
//  Scan orchestration and the weekly background schedule, split out of
//  AppModel so the god class sheds its scan plumbing while behavior
//  stays identical. The width-limited fan-out passes live in
//  ScanCoordinator+Passes.swift, which reads the state declared here —
//  an extension in another file cannot reach `private` members, so
//  everything the passes touch stays internal.
//
//  Concurrency model
//  ─────────────────
//  The coordinator is @MainActor: every property the UI reads is
//  main-actor state. Blocking filesystem work (sizing, discovery) runs
//  through `offMain`, which executes on the global concurrent executor,
//  off the main thread. Scans fan out through a task group with bounded
//  width so disk I/O never saturates the cooperative thread pool.
//

import Foundation
import Observation
import ReclaimKit

@MainActor
@Observable
public final class ScanCoordinator {
    // MARK: - Constants

    /// Maximum directory walks in flight at once. Disk-bound work gains
    /// little from more parallelism and would block cooperative threads.
    static let maxConcurrentScans = 4

    /// How often the background scan runs while the app is open.
    public static let backgroundScanInterval: TimeInterval = 7 * 24 * 3600

    // MARK: - Session state

    /// When the last *completed* (non-cancelled) scan finished. Anchors
    /// the weekly background schedule and, being observable, keeps the
    /// footer's "next background scan" line live.
    public private(set) var lastCompletedScanDate: Date?

    @ObservationIgnored
    private(set) var scanTask: Task<Void, Never>?

    // MARK: - Collaborators

    @ObservationIgnored
    let results: TargetResultsModel
    @ObservationIgnored
    let projects: ProjectsModel
    @ObservationIgnored
    let activity: ActivityModel
    @ObservationIgnored
    private let selection: SelectionModel
    @ObservationIgnored
    private let breakdowns: BreakdownModel
    @ObservationIgnored
    private let settings: SettingsStore

    @ObservationIgnored
    let scanExecutor: ScanExecutor
    @ObservationIgnored
    let projectScanExecutor: ProjectScanExecutor
    @ObservationIgnored
    private let fullDiskAccessProbe: @Sendable () -> Bool?

    // MARK: - Persisted state

    @ObservationIgnored
    private let defaults: UserDefaults

    private enum DefaultsKey {
        static let lastScanDate = "state.lastScanDate"
    }

    // MARK: - Init

    public init(
        executors: Executors,
        results: TargetResultsModel,
        selection: SelectionModel,
        projects: ProjectsModel,
        breakdowns: BreakdownModel,
        settings: SettingsStore,
        activity: ActivityModel,
        defaults: UserDefaults
    ) {
        self.results = results
        self.selection = selection
        self.projects = projects
        self.breakdowns = breakdowns
        self.settings = settings
        self.activity = activity
        self.defaults = defaults
        self.scanExecutor = executors.scan
        self.projectScanExecutor = executors.projectScan
        self.fullDiskAccessProbe = executors.fullDiskAccess
        self.lastCompletedScanDate = defaults.object(forKey: DefaultsKey.lastScanDate) as? Date
    }

    // MARK: - Background scanning

    /// When the next automatic scan is due, or `nil` when disabled or
    /// no scan has happened yet.
    public var nextBackgroundScanDate: Date? {
        guard settings.weeklyScanEnabled else { return nil }
        guard let last = lastCompletedScanDate else { return nil }
        return last.addingTimeInterval(Self.backgroundScanInterval)
    }

    /// Start a scan if the weekly background scan is enabled and due.
    /// Called periodically by the app layer while Reclaim is running.
    /// Defers while the confirmation sheet is up — a background scan
    /// must never clear a selection the user is actively reviewing.
    public func runBackgroundScanIfDue(now: Date = .now) {
        guard settings.weeklyScanEnabled, !activity.isScanning, !activity.isCleaning, !activity.isReviewingSelection else { return }
        guard let next = nextBackgroundScanDate else { return }
        if now >= next { scanAll() }
    }

    // MARK: - Scanning

    /// Scan every target with bounded parallelism.
    public func scanAll() {
        guard !activity.isScanning, !activity.isCleaning else { return }
        activity.isScanning = true
        activity.isCancellingScan = false
        selection.clearForScan()
        activity.lastCleanSummary = nil
        breakdowns.invalidateAll()
        projects.resetForScan()
        results.scanRealRoots.removeAll()
        activity.scanProgress = ScanProgress(
            completed: 0, total: results.targets.count + projects.devRoots.count,
            currentTargetName: "", currentPath: ""
        )
        for target in results.targets {
            results.setStatus(.scanning, for: target.id)
        }

        let probe = fullDiskAccessProbe
        scanTask = Task { [targets = results.targets] in
            // Keep the process off App Nap for the duration: a scan with
            // the window closed (menu-bar-only) would otherwise be
            // throttled, and the weekly background scan is exactly that
            // case.
            let processActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated], reason: "Scanning for reclaimable storage"
            )
            defer { ProcessInfo.processInfo.endActivity(processActivity) }
            self.results.hasFullDiskAccess = await offMain { probe() }
            await self.runScan(of: targets)
            // Any rows still marked scanning were cancelled mid-flight.
            for target in targets where self.results.statuses[target.id] == .scanning {
                self.results.setStatus(.idle, for: target.id)
            }
            await self.runProjectScan()
            self.results.lastScan = .now
            self.results.lastScanWasComplete = !Task.isCancelled
            // Only a completed scan anchors the weekly schedule — a scan
            // the user stopped after two seconds must not push the next
            // automatic scan a full week out.
            if !Task.isCancelled {
                self.lastCompletedScanDate = .now
                self.defaults.set(Date.now, forKey: DefaultsKey.lastScanDate)
            }
            self.activity.isScanning = false
            self.activity.isCancellingScan = false
            self.activity.scanProgress = nil
            self.scanTask = nil
            self.applyPostScanSelection()
            self.results.refreshVolumeSpace()
        }
    }

    /// Mirrors the design's post-scan behavior: Safe items come ticked
    /// (plus Caution when the setting opts in), so one click cleans.
    /// Targets the user excluded from automatic selection stay unticked.
    private func applyPostScanSelection() {
        for target in results.targets where selection.isSelectable(target) {
            guard !selection.isExcludedFromAutoSelect(target) else { continue }
            let wanted = target.safety == .safe
                || (settings.preselectCaution && target.safety == .caution)
            if wanted {
                selection.insertForPostScan(target.id)
            }
        }
    }

    public func cancelScan() {
        guard scanTask != nil else { return }
        activity.isCancellingScan = true
        scanTask?.cancel()
    }

    /// Tilde-form location shown while a target is being processed.
    nonisolated static func displayLocation(of target: CleanupTarget) -> String {
        if let pattern = target.pathPatterns.first { return pattern }
        if case .command(let spec) = target.strategy { return spec.displayCommand }
        return target.name
    }
}
