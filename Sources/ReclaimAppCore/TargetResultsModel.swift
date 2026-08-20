//
//  TargetResultsModel.swift
//  ReclaimAppCore
//
//  Per-target scan results — statuses, the scan-time symlink pins, the
//  full-disk-access verdict and volume capacity — split out of AppModel
//  so the god class sheds its result state while behavior stays
//  identical. Visibility honors the user's settings, so the store is a
//  dependency; volume capacity comes from an injected probe.
//

import Foundation
import Observation
import ReclaimKit

@Observable
public final class TargetResultsModel {
    // MARK: - Catalogue

    /// All known targets, in registry order.
    public let targets: [CleanupTarget]

    // MARK: - Session state

    /// Scan status per target id. Missing entry ⇒ `.idle`.
    public internal(set) var statuses: [CleanupTarget.ID: TargetStatus] = [:]

    public internal(set) var lastScan: Date?

    /// Whether the most recent scan ran to completion. `false` means it
    /// was stopped early: measurements on screen are real but partial.
    /// Meaningful only once `lastScan` is non-nil.
    public internal(set) var lastScanWasComplete = true

    /// Whether the process can read TCC-protected locations. Evaluated
    /// at scan time; `nil` before the first scan or when indeterminate.
    public internal(set) var hasFullDiskAccess: Bool?

    /// Capacity of the volume holding the user's data, for the disk
    /// card. Refreshed around scans and cleans.
    public internal(set) var volumeSpace: VolumeSpace?

    /// Symlink-resolved (real) form of each target's roots, captured at
    /// scan time. Cleaning refuses any cleanup path whose ancestry no
    /// longer resolves to one of these — the defence against a cache
    /// directory being swapped for a symlink between scan and clean,
    /// which would otherwise redirect deletion outside the target.
    @ObservationIgnored
    var scanRealRoots: [CleanupTarget.ID: Set<String>] = [:]

    private let settings: SettingsStore

    @ObservationIgnored
    private let volumeProbe: @Sendable () -> VolumeSpace?

    // MARK: - Init

    public init(
        targets: [CleanupTarget],
        settings: SettingsStore,
        volumeProbe: @escaping @Sendable () -> VolumeSpace?
    ) {
        self.targets = targets
        self.settings = settings
        self.volumeProbe = volumeProbe
    }

    // MARK: - Derived state

    public func status(of id: CleanupTarget.ID) -> TargetStatus {
        statuses[id] ?? .idle
    }

    /// Measured bytes of one target (0 while unmeasured).
    public func bytes(of target: CleanupTarget) -> Int64 {
        status(of: target.id).bytes ?? 0
    }

    /// Record one target's freshly resolved status.
    func setStatus(_ status: TargetStatus, for id: CleanupTarget.ID) {
        statuses[id] = status
    }

    /// Targets shown for a category, honoring the "show not installed"
    /// and "show empty" settings once a scan has happened.
    public func visibleTargets(in category: ToolCategory) -> [CleanupTarget] {
        let all = targets.filter { $0.category == category }
        guard lastScan != nil else { return all }
        return all.filter(isVisibleAfterScan)
    }

    /// Every visible target across all categories, in registry order —
    /// what the "Review everything" browser lists.
    public var allVisibleTargets: [CleanupTarget] {
        guard lastScan != nil else { return targets }
        return targets.filter(isVisibleAfterScan)
    }

    private func isVisibleAfterScan(_ target: CleanupTarget) -> Bool {
        switch status(of: target.id) {
        case .notInstalled:
            return settings.showNotInstalled
        case .measured(let measurement, _, _)
            where measurement.bytes == 0 && measurement.inaccessibleItems == 0:
            // Provably empty. A lower-bound zero (unreadable entries)
            // stays visible — it may not actually be empty.
            return settings.showEmpty
        default:
            return true
        }
    }

    // MARK: - Volume space

    func refreshVolumeSpace() {
        let probe = volumeProbe
        Task {
            self.volumeSpace = await Self.measure(probe)
        }
    }

    /// Measures the volume on the concurrent executor — the blocking
    /// filesystem boundary of a capacity refresh.
    @concurrent
    private static func measure(_ probe: @Sendable () -> VolumeSpace?) async -> VolumeSpace? {
        probe()
    }
}
