//
//  AppModel.swift
//  Reclaim
//
//  The single observable source of truth for the UI. Owns per-target
//  scan status, selection, settings, and orchestrates background work.
//
//  Concurrency model
//  ─────────────────
//  The model is @MainActor: every property the UI reads is main-actor
//  state. Blocking filesystem work (sizing, deleting) runs in
//  `nonisolated` async helpers, which — with this package's settings
//  (no NonisolatedNonsendingByDefault / no default MainActor isolation)
//  — execute on the global concurrent executor, off the main thread.
//  Scans fan out through a task group with bounded width so disk I/O
//  never saturates the cooperative thread pool.
//

import Foundation
import Observation
import ReclaimKit

@MainActor
@Observable
final class AppModel {
    // MARK: - Constants

    /// Maximum directory walks in flight at once. Disk-bound work gains
    /// little from more parallelism and would block cooperative threads.
    private static let maxConcurrentScans = 4

    // MARK: - Catalogue

    /// All known targets, in registry order.
    let targets: [CleanupTarget]

    // MARK: - Session state

    /// Scan status per target id. Missing entry ⇒ `.idle`.
    private(set) var statuses: [CleanupTarget.ID: TargetStatus] = [:]

    /// Targets the user has ticked for cleaning.
    private(set) var selection: Set<CleanupTarget.ID> = []

    private(set) var isScanning = false
    private(set) var isCleaning = false
    private(set) var lastScan: Date?

    /// Set when a cleanup pass finishes; the UI presents it as an alert
    /// and clears it by assigning `nil`.
    var lastCleanSummary: CleanSummary?

    @ObservationIgnored
    private var scanTask: Task<Void, Never>?

    // MARK: - Persisted settings

    private let defaults: UserDefaults

    private enum DefaultsKey {
        static let disposal = "settings.disposal"
        static let showNotInstalled = "settings.showNotInstalled"
    }

    /// Trash (default) or permanent deletion. Backed by UserDefaults via
    /// the ObservationRegistrar so views update when Settings change it.
    var disposal: Disposal {
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
    var showNotInstalled: Bool {
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

    init(
        targets: [CleanupTarget] = TargetRegistry.all,
        defaults: UserDefaults = .standard
    ) {
        self.targets = targets
        self.defaults = defaults
    }

    // MARK: - Derived state

    func status(of id: CleanupTarget.ID) -> TargetStatus {
        statuses[id] ?? .idle
    }

    /// Targets shown for a category, honoring the "hide not installed"
    /// setting once a scan has happened.
    func visibleTargets(in category: ToolCategory) -> [CleanupTarget] {
        let all = targets.filter { $0.category == category }
        guard lastScan != nil, !showNotInstalled else { return all }
        return all.filter { status(of: $0.id) != .notInstalled }
    }

    /// Everything measured, including manual-only items like Docker.
    var totalFoundBytes: Int64 {
        targets.reduce(0) { $0 + (status(of: $1.id).bytes ?? 0) }
    }

    /// Only what Reclaim itself can clean.
    var cleanableBytes: Int64 {
        targets.reduce(0) { sum, target in
            guard target.strategy.isCleanable else { return sum }
            return sum + (status(of: target.id).bytes ?? 0)
        }
    }

    /// Bytes covered by the current selection.
    var selectedBytes: Int64 {
        selection.reduce(0) { $0 + (status(of: $1).bytes ?? 0) }
    }

    struct CategoryTotal: Identifiable {
        let category: ToolCategory
        let bytes: Int64
        var id: ToolCategory.ID { category.id }
    }

    /// Per-category measured totals in category display order.
    func categoryTotals() -> [CategoryTotal] {
        ToolCategory.allCases.map { category in
            let bytes = targets
                .filter { $0.category == category }
                .reduce(Int64(0)) { $0 + (status(of: $1.id).bytes ?? 0) }
            return CategoryTotal(category: category, bytes: bytes)
        }
    }

    /// Formatted total for a sidebar badge, or `nil` before any scan.
    func formattedCategoryTotal(_ category: ToolCategory) -> String? {
        guard lastScan != nil else { return nil }
        let bytes = categoryTotals().first { $0.category == category }?.bytes ?? 0
        return bytes > 0 ? bytes.formattedBytes : nil
    }

    /// The largest measured targets, for the overview list.
    func largestTargets(limit: Int) -> [CleanupTarget] {
        targets
            .filter { (status(of: $0.id).bytes ?? 0) > 0 }
            .sorted { (status(of: $0.id).bytes ?? 0) > (status(of: $1.id).bytes ?? 0) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Selection

    /// Whether the row's checkbox is enabled.
    func isSelectable(_ target: CleanupTarget) -> Bool {
        guard target.strategy.isCleanable, !isScanning, !isCleaning else { return false }
        switch status(of: target.id) {
        case .measured(let measurement, _, _): return measurement.bytes > 0
        case .unmeasurable: return true
        default: return false
        }
    }

    func isSelected(_ target: CleanupTarget) -> Bool {
        selection.contains(target.id)
    }

    func setSelected(_ target: CleanupTarget, _ selected: Bool) {
        if selected, isSelectable(target) {
            selection.insert(target.id)
        } else {
            selection.remove(target.id)
        }
    }

    /// Select every selectable target rated ``SafetyLevel/safe``.
    func selectAllSafe() {
        for target in targets where target.safety == .safe && isSelectable(target) {
            selection.insert(target.id)
        }
    }

    func clearSelection() {
        selection.removeAll()
    }

    // MARK: - Scanning

    /// Scan every target with bounded parallelism.
    func scanAll() {
        guard !isScanning, !isCleaning else { return }
        isScanning = true
        selection.removeAll()
        lastCleanSummary = nil
        for target in targets {
            statuses[target.id] = .scanning
        }

        scanTask = Task { [targets] in
            await self.runScan(of: targets)
            // Any rows still marked scanning were cancelled mid-flight.
            for target in targets where self.statuses[target.id] == .scanning {
                self.statuses[target.id] = .idle
            }
            self.lastScan = .now
            self.isScanning = false
            self.scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    /// Fan out scans through a width-limited task group. Runs on the
    /// main actor; the blocking work happens inside the child tasks,
    /// which execute nonisolated on the global executor.
    private func runScan(of targets: [CleanupTarget]) async {
        await withTaskGroup(of: (CleanupTarget.ID, TargetStatus).self) { group in
            var pending = targets.makeIterator()

            @discardableResult
            func startNext() -> Bool {
                guard let target = pending.next() else { return false }
                group.addTask {
                    (target.id, TargetScanner().scan(target))
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
    func cleanSelected() {
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

        Task {
            var summary = CleanSummary(disposal: chosenDisposal)

            // Sequential on purpose: cleanup should be predictable and
            // easy to interrupt, and it is I/O-bound anyway.
            for job in jobs {
                self.statuses[job.target.id] = .scanning

                let outcome = await Self.backgroundClean(
                    job.target, paths: job.paths, disposal: chosenDisposal
                )
                summary.cleanedTargets += 1
                summary.failures.append(contentsOf: outcome.failures.map {
                    "\(job.target.name) — \($0.message)"
                })

                let refreshed = await Self.backgroundScan(job.target)
                self.statuses[job.target.id] = refreshed
                summary.reclaimedBytes += max(0, job.bytesBefore - (refreshed.bytes ?? 0))
                self.selection.remove(job.target.id)
            }

            self.lastCleanSummary = summary
            self.isCleaning = false
        }
    }

    // MARK: - Background helpers

    // Nonisolated async: with this package's settings these hop to the
    // global concurrent executor, keeping blocking I/O off the main
    // thread. If `NonisolatedNonsendingByDefault` is ever enabled,
    // annotate these `@concurrent` to preserve that behavior.

    private nonisolated static func backgroundScan(
        _ target: CleanupTarget
    ) async -> TargetStatus {
        TargetScanner().scan(target)
    }

    private nonisolated static func backgroundClean(
        _ target: CleanupTarget,
        paths: [URL],
        disposal: Disposal
    ) async -> CleanOutcome {
        CleanupEngine().clean(target, resolvedPaths: paths, disposal: disposal)
    }
}
