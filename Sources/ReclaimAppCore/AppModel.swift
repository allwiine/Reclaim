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
        /// 1-based position within this pass.
        public let index: Int
        public let total: Int
    }

    /// Non-nil while a clean pass is processing a target.
    public private(set) var cleanProgress: CleanProgress?

    /// Whether the process can read TCC-protected locations. Evaluated
    /// at scan time; `nil` before the first scan or when indeterminate.
    public private(set) var hasFullDiskAccess: Bool?

    @ObservationIgnored
    private(set) var scanTask: Task<Void, Never>?
    @ObservationIgnored
    private(set) var cleanTask: Task<Void, Never>?

    @ObservationIgnored
    private let scanExecutor: ScanExecutor
    @ObservationIgnored
    private let cleanExecutor: CleanExecutor
    @ObservationIgnored
    private let fullDiskAccessProbe: @Sendable () -> Bool?

    // MARK: - Persisted settings

    private let defaults: UserDefaults

    private enum DefaultsKey {
        static let disposal = "settings.disposal"
        static let showNotInstalled = "settings.showNotInstalled"
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
            withMutation(keyPath: \.disposal) {
                defaults.set(newValue.rawValue, forKey: DefaultsKey.disposal)
            }
        }
    }

    /// Whether tools that were not found on this Mac stay visible.
    public var showNotInstalled: Bool {
        get {
            access(keyPath: \.showNotInstalled)
            return defaults.object(forKey: DefaultsKey.showNotInstalled) as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.showNotInstalled) {
                defaults.set(newValue, forKey: DefaultsKey.showNotInstalled)
            }
        }
    }

    // MARK: - Init

    public init(
        targets: [CleanupTarget] = TargetRegistry.all,
        defaults: UserDefaults = .standard,
        scanExecutor: @escaping ScanExecutor = { TargetScanner().scan($0) },
        cleanExecutor: @escaping CleanExecutor = {
            CleanupEngine().clean($0, resolvedPaths: $1, disposal: $2)
        },
        fullDiskAccessProbe: @escaping @Sendable () -> Bool? = {
            FullDiskAccessProbe().check()
        }
    ) {
        self.targets = targets
        self.defaults = defaults
        self.scanExecutor = scanExecutor
        self.cleanExecutor = cleanExecutor
        self.fullDiskAccessProbe = fullDiskAccessProbe
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
            self.isScanning = false
            self.scanTask = nil
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

            @discardableResult
            func startNext() -> Bool {
                guard let target = pending.next() else { return false }
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
                startNext()
            }
        }
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
                    targetName: job.target.name, index: index + 1, total: jobs.count
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
                    "\(job.target.name) — \($0.message)"
                })

                let refreshed = await Self.offMain { scan(job.target) }
                self.statuses[job.target.id] = refreshed
                summary.reclaimedBytes += max(0, job.bytesBefore - (refreshed.bytes ?? 0))
                self.selection.remove(job.target.id)
            }

            self.cleanProgress = nil
            self.lastCleanSummary = summary
            self.isCleaning = false
            self.cleanTask = nil
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
}
