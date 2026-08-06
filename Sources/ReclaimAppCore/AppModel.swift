//
//  AppModel.swift
//  ReclaimAppCore
//
//  The single observable source of truth for the UI. Owns per-target
//  scan status, selection, settings, and orchestrates background work.
//  Lives in a UI-free library target so the whole orchestration layer
//  is unit-testable; the scan/clean executors are injectable seams.
//
//  Concurrency model
//  ─────────────────
//  The model is @MainActor: every property the UI reads is main-actor
//  state. Blocking filesystem work (sizing, deleting) runs through
//  `offMain`, a `nonisolated` async helper, which — with this package's
//  settings (no NonisolatedNonsendingByDefault / no default MainActor
//  isolation) — executes on the global concurrent executor, off the
//  main thread. Scans fan out through a task group with bounded width
//  so disk I/O never saturates the cooperative thread pool.
//

import Foundation
import Observation
import ReclaimKit

@MainActor
@Observable
public final class AppModel {
    // MARK: - Seams

    /// Produces a status for one target. Blocking; called off-main.
    public typealias ScanExecutor = @Sendable (CleanupTarget) -> TargetStatus
    /// Cleans one target's scan-time paths. Blocking; called off-main.
    public typealias CleanExecutor = @Sendable (CleanupTarget, [URL], Disposal) -> CleanOutcome
    /// Sizes a measured target's individual contents. Blocking; called
    /// off-main. `nil` means the computation was cancelled.
    public typealias BreakdownExecutor = @Sendable (TargetStatus) -> [BreakdownEntry]?

    // MARK: - Constants

    /// Maximum directory walks in flight at once. Disk-bound work gains
    /// little from more parallelism and would block cooperative threads.
    private static let maxConcurrentScans = 4

    // MARK: - Catalogue

    /// All known targets, in registry order.
    public let targets: [CleanupTarget]

    // MARK: - Session state

    /// Scan status per target id. Missing entry ⇒ `.idle`.
    public private(set) var statuses: [CleanupTarget.ID: TargetStatus] = [:]

    /// Targets the user has ticked for cleaning.
    public private(set) var selection: Set<CleanupTarget.ID> = []

    public private(set) var isScanning = false
    public private(set) var isCleaning = false
    public private(set) var lastScan: Date?

    /// Live progress of the running scan pass, for the scanning screen.
    public struct ScanProgress: Equatable, Sendable {
        /// Targets fully measured so far.
        public let completed: Int
        public let total: Int
        /// Name of the most recently started target.
        public let currentTargetName: String
        /// Tilde-form location being walked, or the command being probed.
        public let currentPath: String

        public var fraction: Double {
            total > 0 ? Double(completed) / Double(total) : 0
        }
    }

    /// Non-nil while a scan pass is running.
    public private(set) var scanProgress: ScanProgress?
    /// Whether the most recent scan ran to completion. `false` means it
    /// was stopped early: measurements on screen are real but partial.
    /// Meaningful only once `lastScan` is non-nil.
    public private(set) var lastScanWasComplete = true

    /// Set when a cleanup pass finishes; the UI presents it as an alert
    /// and clears it by assigning `nil`.
    public var lastCleanSummary: CleanSummary?

    /// The target currently being cleaned, for progress UI.
    public struct CleanProgress: Equatable, Sendable {
        public let targetName: String
        /// Tilde-form location being cleaned, when known.
        public let targetPath: String?
        /// 1-based position within this pass.
        public let index: Int
        public let total: Int

        public var fraction: Double {
            total > 0 ? Double(index - 1) / Double(total) : 0
        }
    }

    /// Non-nil while a clean pass is processing a target.
    public private(set) var cleanProgress: CleanProgress?

    /// Whether the process can read TCC-protected locations. Evaluated
    /// at scan time; `nil` before the first scan or when indeterminate.
    public private(set) var hasFullDiskAccess: Bool?

    /// Capacity of the volume holding the user's data, for the disk
    /// card. Refreshed around scans and cleans.
    public private(set) var volumeSpace: VolumeSpace?

    /// Past clean passes, newest first.
    public private(set) var history: [CleanHistoryEntry]

    /// On-demand "largest contents" per target, cached per scan.
    public private(set) var breakdowns: [CleanupTarget.ID: [BreakdownEntry]] = [:]

    @ObservationIgnored
    private(set) var scanTask: Task<Void, Never>?
    @ObservationIgnored
    private(set) var cleanTask: Task<Void, Never>?
    @ObservationIgnored
    private var breakdownTasks: [CleanupTarget.ID: Task<Void, Never>] = [:]

    @ObservationIgnored
    private let scanExecutor: ScanExecutor
    @ObservationIgnored
    private let cleanExecutor: CleanExecutor
    @ObservationIgnored
    private let breakdownExecutor: BreakdownExecutor
    @ObservationIgnored
    private let fullDiskAccessProbe: @Sendable () -> Bool?
    @ObservationIgnored
    private let volumeProbe: @Sendable () -> VolumeSpace?
    @ObservationIgnored
    private let historyStore: CleanHistoryStore

    // MARK: - Persisted settings

    private let defaults: UserDefaults

    private enum DefaultsKey {
        static let disposal = "settings.disposal"
        static let showNotInstalled = "settings.showNotInstalled"
        static let preselectCaution = "settings.preselectCaution"
        static let dryRun = "settings.dryRun"
        static let weeklyScan = "settings.weeklyScan"
        static let notifyLargeReclaimable = "settings.notifyLargeReclaimable"
        static let menuBarExtra = "settings.menuBarExtra"
        static let lastScanDate = "state.lastScanDate"
    }

    /// Reads a Bool setting through the ObservationRegistrar so views
    /// update when it changes; `fallback` applies when never set.
    private func boolSetting<Member>(
        _ keyPath: KeyPath<AppModel, Member>, key: String, fallback: Bool
    ) -> Bool {
        access(keyPath: keyPath)
        return defaults.object(forKey: key) as? Bool ?? fallback
    }

    private func setBoolSetting<Member>(
        _ keyPath: KeyPath<AppModel, Member>, key: String, to newValue: Bool
    ) {
        // Skip no-op writes: SwiftUI bindings (e.g. MenuBarExtra's
        // isInserted) can re-assign the current value during scene
        // evaluation, and an unconditional withMutation would spin an
        // invalidate-reevaluate loop.
        guard (defaults.object(forKey: key) as? Bool) != newValue else { return }
        withMutation(keyPath: keyPath) {
            defaults.set(newValue, forKey: key)
        }
    }

    /// Trash (default) or permanent deletion. Backed by UserDefaults via
    /// the ObservationRegistrar so views update when Settings change it.
    public var disposal: Disposal {
        get {
            access(keyPath: \.disposal)
            let raw = defaults.string(forKey: DefaultsKey.disposal) ?? ""
            return Disposal(rawValue: raw) ?? .trash
        }
        set {
            guard newValue != disposal else { return }
            withMutation(keyPath: \.disposal) {
                defaults.set(newValue.rawValue, forKey: DefaultsKey.disposal)
            }
        }
    }

    /// Whether tools that were not found on this Mac stay visible.
    public var showNotInstalled: Bool {
        get { boolSetting(\.showNotInstalled, key: DefaultsKey.showNotInstalled, fallback: false) }
        set { setBoolSetting(\.showNotInstalled, key: DefaultsKey.showNotInstalled, to: newValue) }
    }

    /// Whether Caution-rated items join the post-scan preselection.
    /// Off by default — only Safe items come ticked after a scan.
    public var preselectCaution: Bool {
        get { boolSetting(\.preselectCaution, key: DefaultsKey.preselectCaution, fallback: false) }
        set { setBoolSetting(\.preselectCaution, key: DefaultsKey.preselectCaution, to: newValue) }
    }

    /// Report what a clean pass would remove without touching anything.
    public var dryRun: Bool {
        get { boolSetting(\.dryRun, key: DefaultsKey.dryRun, fallback: false) }
        set { setBoolSetting(\.dryRun, key: DefaultsKey.dryRun, to: newValue) }
    }

    /// Re-scan automatically once a week while Reclaim is running.
    public var weeklyScanEnabled: Bool {
        get { boolSetting(\.weeklyScanEnabled, key: DefaultsKey.weeklyScan, fallback: true) }
        set { setBoolSetting(\.weeklyScanEnabled, key: DefaultsKey.weeklyScan, to: newValue) }
    }

    /// Post a notification when a background scan finds more than
    /// ``notificationThresholdBytes`` reclaimable.
    public var notifyLargeReclaimable: Bool {
        get { boolSetting(\.notifyLargeReclaimable, key: DefaultsKey.notifyLargeReclaimable, fallback: false) }
        set { setBoolSetting(\.notifyLargeReclaimable, key: DefaultsKey.notifyLargeReclaimable, to: newValue) }
    }

    /// Whether the compact menu bar summary is shown.
    public var menuBarExtraEnabled: Bool {
        get { boolSetting(\.menuBarExtraEnabled, key: DefaultsKey.menuBarExtra, fallback: true) }
        set { setBoolSetting(\.menuBarExtraEnabled, key: DefaultsKey.menuBarExtra, to: newValue) }
    }

    /// Reclaimable size that qualifies as "worth a notification".
    public static let notificationThresholdBytes: Int64 = 25_000_000_000

    /// How often the background scan runs while the app is open.
    public static let backgroundScanInterval: TimeInterval = 7 * 24 * 3600

    // MARK: - Init

    public init(
        targets: [CleanupTarget] = TargetRegistry.all,
        defaults: UserDefaults = .standard,
        scanExecutor: @escaping ScanExecutor = { TargetScanner().scan($0) },
        cleanExecutor: @escaping CleanExecutor = {
            CleanupEngine().clean($0, resolvedPaths: $1, disposal: $2)
        },
        breakdownExecutor: @escaping BreakdownExecutor = {
            try? BreakdownSizer().largestContents(of: $0)
        },
        fullDiskAccessProbe: @escaping @Sendable () -> Bool? = {
            FullDiskAccessProbe().check()
        },
        volumeProbe: @escaping @Sendable () -> VolumeSpace? = {
            VolumeSpaceProbe().measure()
        },
        historyStore: CleanHistoryStore = CleanHistoryStore()
    ) {
        self.targets = targets
        self.defaults = defaults
        self.scanExecutor = scanExecutor
        self.cleanExecutor = cleanExecutor
        self.breakdownExecutor = breakdownExecutor
        self.fullDiskAccessProbe = fullDiskAccessProbe
        self.volumeProbe = volumeProbe
        self.historyStore = historyStore
        self.history = historyStore.load().sorted { $0.date > $1.date }
        refreshVolumeSpace()
    }

    // MARK: - Derived state

    public func status(of id: CleanupTarget.ID) -> TargetStatus {
        statuses[id] ?? .idle
    }

    /// Targets shown for a category, honoring the "hide not installed"
    /// setting once a scan has happened.
    public func visibleTargets(in category: ToolCategory) -> [CleanupTarget] {
        let all = targets.filter { $0.category == category }
        guard lastScan != nil, !showNotInstalled else { return all }
        return all.filter { status(of: $0.id) != .notInstalled }
    }

    /// Everything measured, including manual-only items like Docker.
    public var totalFoundBytes: Int64 {
        targets.reduce(0) { $0 + (status(of: $1.id).bytes ?? 0) }
    }

    /// Only what Reclaim itself can clean.
    public var cleanableBytes: Int64 {
        targets.reduce(0) { sum, target in
            guard target.strategy.isCleanable else { return sum }
            return sum + (status(of: target.id).bytes ?? 0)
        }
    }

    /// Bytes covered by the current selection.
    public var selectedBytes: Int64 {
        selection.reduce(0) { $0 + (status(of: $1).bytes ?? 0) }
    }

    public struct CategoryTotal: Identifiable {
        public let category: ToolCategory
        public let bytes: Int64
        public var id: ToolCategory.ID { category.id }
    }

    /// Per-category measured totals in category display order.
    public func categoryTotals() -> [CategoryTotal] {
        ToolCategory.allCases.map { category in
            let bytes = targets
                .filter { $0.category == category }
                .reduce(Int64(0)) { $0 + (status(of: $1.id).bytes ?? 0) }
            return CategoryTotal(category: category, bytes: bytes)
        }
    }

    /// Measured total for a sidebar badge, or `nil` before any scan or
    /// when nothing in the category was measured.
    public func categoryTotalBytes(_ category: ToolCategory) -> Int64? {
        guard lastScan != nil else { return nil }
        let bytes = categoryTotals().first { $0.category == category }?.bytes ?? 0
        return bytes > 0 ? bytes : nil
    }

    /// The largest measured targets, for the overview list.
    public func largestTargets(limit: Int) -> [CleanupTarget] {
        targets
            .filter { (status(of: $0.id).bytes ?? 0) > 0 }
            .sorted { (status(of: $0.id).bytes ?? 0) > (status(of: $1.id).bytes ?? 0) }
            .prefix(limit)
            .map { $0 }
    }

    /// Measured bytes of one target (0 while unmeasured).
    public func bytes(of target: CleanupTarget) -> Int64 {
        status(of: target.id).bytes ?? 0
    }

    /// What the one-click "reclaim safe space" action covers: measured,
    /// cleanable, Safe-rated bytes.
    public var safeReclaimableBytes: Int64 {
        targets.reduce(0) {
            $1.safety == .safe && $1.strategy.isCleanable ? $0 + bytes(of: $1) : $0
        }
    }

    /// Number of Safe-rated targets with something to clean.
    public var safeReclaimableCount: Int {
        targets.count { $0.safety == .safe && $0.strategy.isCleanable && bytes(of: $0) > 0 }
    }

    /// Measured bytes needing a decision first (Caution + Destructive,
    /// including tool-managed items like Docker).
    public var reviewBytes: Int64 {
        targets.reduce(0) { $1.safety == .safe ? $0 : $0 + bytes(of: $1) }
    }

    /// Number of measured targets needing a decision first.
    public var reviewCount: Int {
        targets.count { $0.safety != .safe && bytes(of: $0) > 0 }
    }

    /// Measured targets Reclaim will not delete itself — their own tool
    /// has to do it (Docker, the Go toolchain). Drives the "needs your
    /// attention" cards.
    public var manualTargets: [CleanupTarget] {
        targets.filter { !$0.strategy.isCleanable && bytes(of: $0) > 0 }
    }

    /// All-time reclaimed space across recorded cleans.
    public var reclaimedAllTimeBytes: Int64 {
        history.reduce(0) { $0 + $1.reclaimedBytes }
    }

    // MARK: - Background scanning

    /// When the next automatic scan is due, or `nil` when disabled or
    /// no scan has happened yet.
    public var nextBackgroundScanDate: Date? {
        guard weeklyScanEnabled else { return nil }
        guard let last = defaults.object(forKey: DefaultsKey.lastScanDate) as? Date else {
            return nil
        }
        return last.addingTimeInterval(Self.backgroundScanInterval)
    }

    /// Start a scan if the weekly background scan is enabled and due.
    /// Called periodically by the app layer while Reclaim is running.
    public func runBackgroundScanIfDue(now: Date = .now) {
        guard weeklyScanEnabled, !isScanning, !isCleaning else { return }
        guard let next = nextBackgroundScanDate else { return }
        if now >= next { scanAll() }
    }

    // MARK: - Contents breakdown

    /// Kick off (or reuse) the "largest contents" computation for a
    /// measured target. Results land in ``breakdowns``.
    public func loadBreakdown(for target: CleanupTarget) {
        guard breakdowns[target.id] == nil, breakdownTasks[target.id] == nil else { return }
        let current = status(of: target.id)
        guard case .measured = current else { return }

        let compute = breakdownExecutor
        breakdownTasks[target.id] = Task {
            let entries = await Self.offMain { compute(current) }
            if let entries {
                self.breakdowns[target.id] = entries
            }
            self.breakdownTasks[target.id] = nil
        }
    }

    /// Drop cached breakdowns (statuses changed, they may be stale).
    private func invalidateBreakdowns() {
        for task in breakdownTasks.values { task.cancel() }
        breakdownTasks.removeAll()
        breakdowns.removeAll()
    }

    private func refreshVolumeSpace() {
        let probe = volumeProbe
        Task {
            self.volumeSpace = await Self.offMain { probe() }
        }
    }

    // MARK: - Selection

    /// Whether the row's checkbox is enabled.
    public func isSelectable(_ target: CleanupTarget) -> Bool {
        guard target.strategy.isCleanable, !isScanning, !isCleaning else { return false }
        switch status(of: target.id) {
        case .measured(let measurement, _, _): return measurement.bytes > 0
        case .unmeasurable: return true
        default: return false
        }
    }

    public func isSelected(_ target: CleanupTarget) -> Bool {
        selection.contains(target.id)
    }

    /// The selected targets, in registry order.
    public var selectedTargets: [CleanupTarget] {
        targets.filter { selection.contains($0.id) }
    }

    public func setSelected(_ target: CleanupTarget, _ selected: Bool) {
        if selected, isSelectable(target) {
            selection.insert(target.id)
        } else {
            selection.remove(target.id)
        }
    }

    /// Select every selectable target rated ``SafetyLevel/safe``.
    public func selectAllSafe() {
        for target in targets where target.safety == .safe && isSelectable(target) {
            selection.insert(target.id)
        }
    }

    public func clearSelection() {
        selection.removeAll()
    }

    // MARK: - Scanning

    /// Scan every target with bounded parallelism.
    public func scanAll() {
        guard !isScanning, !isCleaning else { return }
        isScanning = true
        selection.removeAll()
        lastCleanSummary = nil
        invalidateBreakdowns()
        scanProgress = ScanProgress(
            completed: 0, total: targets.count, currentTargetName: "", currentPath: ""
        )
        for target in targets {
            statuses[target.id] = .scanning
        }

        let probe = fullDiskAccessProbe
        scanTask = Task { [targets] in
            self.hasFullDiskAccess = await Self.offMain { probe() }
            await self.runScan(of: targets)
            // Any rows still marked scanning were cancelled mid-flight.
            for target in targets where self.statuses[target.id] == .scanning {
                self.statuses[target.id] = .idle
            }
            self.lastScan = .now
            self.lastScanWasComplete = !Task.isCancelled
            self.defaults.set(Date.now, forKey: DefaultsKey.lastScanDate)
            self.isScanning = false
            self.scanProgress = nil
            self.scanTask = nil
            self.applyPostScanSelection()
            self.refreshVolumeSpace()
        }
    }

    /// Mirrors the design's post-scan behavior: Safe items come ticked
    /// (plus Caution when the setting opts in), so one click cleans.
    private func applyPostScanSelection() {
        for target in targets where isSelectable(target) {
            let wanted = target.safety == .safe
                || (preselectCaution && target.safety == .caution)
            if wanted {
                selection.insert(target.id)
            }
        }
    }

    public func cancelScan() {
        scanTask?.cancel()
    }

    /// Stop the running clean pass after the in-flight target finishes.
    public func cancelClean() {
        cleanTask?.cancel()
    }

    /// Fan out scans through a width-limited task group. Runs on the
    /// main actor; the blocking work happens inside the child tasks,
    /// which execute nonisolated on the global executor.
    private func runScan(of targets: [CleanupTarget]) async {
        let scan = scanExecutor
        await withTaskGroup(of: (CleanupTarget.ID, TargetStatus).self) { group in
            var pending = targets.makeIterator()
            var completed = 0

            // Nested functions do not inherit the enclosing actor, so
            // spell out the isolation this one needs to touch progress.
            @MainActor
            @discardableResult
            func startNext() -> Bool {
                guard let target = pending.next() else { return false }
                scanProgress = ScanProgress(
                    completed: completed,
                    total: targets.count,
                    currentTargetName: target.name,
                    currentPath: Self.displayLocation(of: target)
                )
                group.addTask {
                    (target.id, scan(target))
                }
                return true
            }

            for _ in 0..<Self.maxConcurrentScans {
                startNext()
            }
            while let (id, resolvedStatus) = await group.next() {
                statuses[id] = resolvedStatus
                completed += 1
                if let progress = scanProgress {
                    scanProgress = ScanProgress(
                        completed: completed,
                        total: progress.total,
                        currentTargetName: progress.currentTargetName,
                        currentPath: progress.currentPath
                    )
                }
                startNext()
            }
        }
    }

    /// Tilde-form location shown while a target is being processed.
    private nonisolated static func displayLocation(of target: CleanupTarget) -> String {
        if let pattern = target.pathPatterns.first { return pattern }
        if case .command(let spec) = target.strategy { return spec.displayCommand }
        return target.name
    }

    // MARK: - Cleaning

    private struct CleanJob {
        let target: CleanupTarget
        let paths: [URL]
        let bytesBefore: Int64
    }

    /// Clean everything currently selected, then re-scan those targets
    /// so the numbers on screen stay truthful.
    public func cleanSelected() {
        guard !isCleaning, !isScanning, !selection.isEmpty else { return }

        let jobs: [CleanJob] = targets.compactMap { target in
            guard selection.contains(target.id), target.strategy.isCleanable else { return nil }
            switch status(of: target.id) {
            case .measured(let measurement, _, let cleanupPaths):
                return CleanJob(target: target, paths: cleanupPaths, bytesBefore: measurement.bytes)
            case .unmeasurable:
                return CleanJob(target: target, paths: [], bytesBefore: 0)
            default:
                return nil
            }
        }
        guard !jobs.isEmpty else { return }

        // A dry run is a report, not a pass: project the numbers from
        // the scan-time snapshot and touch nothing — no engine, no
        // rescan, and the selection stays intact.
        if dryRun {
            var summary = CleanSummary(disposal: disposal)
            summary.isDryRun = true
            for job in jobs {
                summary.itemsRemoved += max(1, job.paths.count)
                summary.cleanedTargets += 1
                summary.reclaimedBytes += job.bytesBefore
                summary.cleaned.append(CleanSummary.CleanedTarget(
                    id: job.target.id,
                    name: job.target.name,
                    category: job.target.category,
                    bytesFreed: job.bytesBefore
                ))
            }
            lastCleanSummary = summary
            return
        }

        isCleaning = true
        let chosenDisposal = disposal
        let scan = scanExecutor
        let clean = cleanExecutor

        cleanTask = Task {
            var summary = CleanSummary(disposal: chosenDisposal)

            // Sequential on purpose: cleanup should be predictable and
            // easy to interrupt, and it is I/O-bound anyway. The
            // cancellation check sits between jobs: the in-flight
            // target always finishes, so nothing is left half-cleaned.
            for (index, job) in jobs.enumerated() {
                if Task.isCancelled {
                    summary.wasStopped = true
                    break
                }
                self.cleanProgress = CleanProgress(
                    targetName: job.target.name,
                    targetPath: job.target.pathPatterns.first,
                    index: index + 1,
                    total: jobs.count
                )
                self.statuses[job.target.id] = .scanning

                let outcome = await Self.offMain {
                    clean(job.target, job.paths, chosenDisposal)
                }
                summary.itemsRemoved += outcome.removedItems
                if outcome.removedItems > 0 {
                    summary.cleanedTargets += 1
                } else if !outcome.failures.isEmpty {
                    summary.failedTargets += 1
                }
                summary.failures.append(contentsOf: outcome.failures.map {
                    localized(
                        "clean.failureLine",
                        defaultValue: "\(job.target.name) — \($0.message)"
                    )
                })

                let refreshed = await Self.offMain { scan(job.target) }
                self.statuses[job.target.id] = refreshed
                self.breakdownTasks[job.target.id]?.cancel()
                self.breakdownTasks[job.target.id] = nil
                self.breakdowns[job.target.id] = nil
                let freed = max(0, job.bytesBefore - (refreshed.bytes ?? 0))
                summary.reclaimedBytes += freed
                if outcome.removedItems > 0 {
                    summary.cleaned.append(CleanSummary.CleanedTarget(
                        id: job.target.id,
                        name: job.target.name,
                        category: job.target.category,
                        bytesFreed: freed
                    ))
                }
                self.selection.remove(job.target.id)
            }

            self.cleanProgress = nil
            self.lastCleanSummary = summary
            self.isCleaning = false
            self.cleanTask = nil
            self.recordHistory(from: summary)
            self.refreshVolumeSpace()
        }
    }

    /// Append a real pass with removals to the persistent history.
    private func recordHistory(from summary: CleanSummary) {
        guard !summary.isDryRun, summary.itemsRemoved > 0 else { return }
        let entry = CleanHistoryEntry(
            date: .now,
            targetNames: summary.cleaned.map(\.name),
            itemsRemoved: summary.itemsRemoved,
            reclaimedBytes: summary.reclaimedBytes
        )
        history.insert(entry, at: 0)
        let store = historyStore
        let snapshot = history
        Task {
            await Self.offMain { store.save(snapshot) }
        }
    }

    // MARK: - Background helpers

    /// Runs blocking work off the main actor. With this package's
    /// settings a `nonisolated` async function hops to the global
    /// concurrent executor. If `NonisolatedNonsendingByDefault` is ever
    /// enabled, annotate this `@concurrent` to preserve that behavior.
    private nonisolated static func offMain<T: Sendable>(
        _ work: @Sendable @escaping () -> T
    ) async -> T {
        work()
    }

    // MARK: - Preview support

    #if DEBUG
    /// Preview-only: install canned scan results so SwiftUI previews
    /// can render every screen without touching the filesystem.
    public func seedForPreview(
        statuses: [CleanupTarget.ID: TargetStatus],
        selection: Set<CleanupTarget.ID> = [],
        history: [CleanHistoryEntry] = [],
        breakdowns: [CleanupTarget.ID: [BreakdownEntry]] = [:],
        volumeSpace: VolumeSpace? = nil,
        hasFullDiskAccess: Bool? = true,
        lastCleanSummary: CleanSummary? = nil
    ) {
        self.statuses = statuses
        self.selection = selection
        self.history = history
        self.breakdowns = breakdowns
        self.volumeSpace = volumeSpace
        self.hasFullDiskAccess = hasFullDiskAccess
        self.lastCleanSummary = lastCleanSummary
        self.lastScan = .now
        self.lastScanWasComplete = true
    }
    #endif
}
