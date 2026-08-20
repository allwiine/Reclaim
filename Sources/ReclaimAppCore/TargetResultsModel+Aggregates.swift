//
//  TargetResultsModel+Aggregates.swift
//  ReclaimAppCore
//
//  Totals derived from the per-target scan results: per-category sums,
//  the largest findings, and the safe/review split the overview reads.
//  Pure reads over `statuses` — no state of their own.
//

import Foundation
import ReclaimKit

public nonisolated struct CategoryTotal: Identifiable {
    public let category: ToolCategory
    public let bytes: Int64
    public var id: ToolCategory.ID { category.id }
}

extension TargetResultsModel {
    /// Per-category measured totals in category display order.
    /// `cleanableOnly` restricts the sum to what Reclaim itself can
    /// clean — the honest figure for anything labeled "reclaimable".
    public func categoryTotals(cleanableOnly: Bool = false) -> [CategoryTotal] {
        ToolCategory.allCases.map { category in
            let bytes = targets
                .filter { $0.category == category && (!cleanableOnly || $0.strategy.isCleanable) }
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
}
