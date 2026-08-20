//
//  BreakdownModel.swift
//  ReclaimAppCore
//
//  On-demand "largest contents" cache per target, split out of AppModel
//  so the god class sheds its breakdown plumbing while behavior stays
//  identical.
//

import Foundation
import Observation
import ReclaimKit

@MainActor
@Observable
public final class BreakdownModel {
    /// On-demand "largest contents" per target, cached per scan.
    public private(set) var entries: [CleanupTarget.ID: [BreakdownEntry]] = [:]

    @ObservationIgnored
    private var breakdownTasks: [CleanupTarget.ID: Task<Void, Never>] = [:]
    /// Invalidation tokens for in-flight breakdown computations. A task
    /// may only publish its result while its token is still current —
    /// a result computed for an old scan must never overwrite fresh state.
    @ObservationIgnored
    private var breakdownTokens: [CleanupTarget.ID: UUID] = [:]

    @ObservationIgnored
    private let results: TargetResultsModel
    @ObservationIgnored
    private let executor: BreakdownExecutor

    public init(results: TargetResultsModel, executor: @escaping BreakdownExecutor) {
        self.results = results
        self.executor = executor
    }

    /// Kick off (or reuse) the "largest contents" computation for a
    /// measured target. Results land in ``entries``.
    public func load(for target: CleanupTarget) {
        guard entries[target.id] == nil, breakdownTasks[target.id] == nil else { return }
        let current = results.status(of: target.id)
        guard case .measured = current else { return }

        let compute = executor
        let token = UUID()
        breakdownTokens[target.id] = token
        breakdownTasks[target.id] = Task {
            let entries = await Self.computeEntries(compute, current)
            // A computation that finished just before an invalidation
            // cancelled it must not publish its (stale) result.
            guard self.breakdownTokens[target.id] == token else { return }
            if let entries {
                self.entries[target.id] = entries
            }
            self.breakdownTasks[target.id] = nil
            self.breakdownTokens[target.id] = nil
        }
    }

    /// Sizes the target's contents on the concurrent executor — the
    /// blocking filesystem boundary of a breakdown load.
    @concurrent
    private static func computeEntries(
        _ compute: BreakdownExecutor, _ status: TargetStatus
    ) async -> [BreakdownEntry]? {
        compute(status)
    }

    /// Drop cached breakdowns (statuses changed, they may be stale).
    func invalidateAll() {
        for task in breakdownTasks.values { task.cancel() }
        breakdownTasks.removeAll()
        breakdownTokens.removeAll()
        entries.removeAll()
    }

    /// Invalidate one target's breakdown (after cleaning re-measured it).
    func invalidate(_ id: CleanupTarget.ID) {
        breakdownTasks[id]?.cancel()
        breakdownTasks[id] = nil
        breakdownTokens[id] = nil
        entries[id] = nil
    }

    // MARK: - Preview support

    #if DEBUG
    /// Preview-only: install canned breakdown entries so SwiftUI previews
    /// can render every screen without touching the filesystem.
    func seed(entries: [CleanupTarget.ID: [BreakdownEntry]]) {
        self.entries = entries
    }
    #endif
}
