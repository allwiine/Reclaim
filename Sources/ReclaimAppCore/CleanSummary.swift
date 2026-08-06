//
//  CleanSummary.swift
//  ReclaimAppCore
//
//  Result of one cleanup pass, presented on the Done screen.
//

import Foundation
import ReclaimKit

/// Aggregated outcome of cleaning the selected targets.
public struct CleanSummary: Equatable, Sendable {
    /// One target processed by the pass, for the results list.
    public struct CleanedTarget: Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let category: ToolCategory
        /// Measurably freed space (post-clean rescan), or the size that
        /// would be freed on a dry run.
        public let bytesFreed: Int64

        public init(id: String, name: String, category: ToolCategory, bytesFreed: Int64) {
            self.id = id
            self.name = name
            self.category = category
            self.bytesFreed = bytesFreed
        }
    }

    /// How removals were performed (affects the wording of the alert).
    public let disposal: Disposal
    /// True when nothing was touched and the numbers are projections.
    public var isDryRun: Bool = false
    public var reclaimedBytes: Int64 = 0
    /// Targets where at least one item was actually removed.
    public var cleanedTargets: Int = 0
    /// Targets where nothing could be removed at all.
    public var failedTargets: Int = 0
    /// Files and folders disposed of across all targets.
    public var itemsRemoved: Int = 0
    /// Whether the pass was stopped before processing every target.
    public var wasStopped: Bool = false
    /// Human-readable failure lines, empty on full success.
    public var failures: [String] = []
    /// Per-target results for targets that had removals, pass order.
    public var cleaned: [CleanedTarget] = []

    public init(disposal: Disposal) {
        self.disposal = disposal
    }
}
