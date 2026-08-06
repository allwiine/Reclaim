//
//  CleanSummary.swift
//  ReclaimAppCore
//
//  Result of one cleanup pass, presented as an alert.
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

    /// Alert body text. Plural agreement ("1 item" / "3 items" and the
    /// Norwegian equivalents) comes from the stringsdict plural rules —
    /// English-only `^[…](inflect: true)` inflection cannot localize.
    public var message: String {
        var lines: [String] = []

        if isDryRun {
            let space = reclaimedBytes.formatted(.byteCount(style: .file))
            lines.append(localized(
                "summary.dryRun",
                defaultValue: "Dry run — nothing was touched. Cleaning this selection would free about \(space)."
            ))
            return lines.joined(separator: "\n")
        }

        if wasStopped {
            lines.append(localized(
                "summary.stoppedEarly",
                defaultValue: "Cleaning was stopped early — not every selected item was processed."
            ))
        }

        if itemsRemoved == 0 {
            lines.append(localized(
                "summary.nothingCleaned",
                defaultValue: "Nothing was cleaned."
            ))
        } else {
            let space = reclaimedBytes.formatted(.byteCount(style: .file))
            switch disposal {
            case .trash:
                lines.append(localized(
                    "summary.movedToTrash",
                    defaultValue: "Moved \(itemsRemoved) items (\(space)) from \(cleanedTargets) locations to the Trash. Empty the Trash to free the space permanently."
                ))
            case .delete:
                lines.append(localized(
                    "summary.deletedPermanently",
                    defaultValue: "Freed \(space) by permanently deleting \(itemsRemoved) items from \(cleanedTargets) locations."
                ))
            }
        }

        if !failures.isEmpty {
            lines.append("")
            lines.append(localized(
                "summary.failuresHeading",
                defaultValue: "Some items could not be cleaned:"
            ))
            lines.append(contentsOf: failures.prefix(5))
            if failures.count > 5 {
                lines.append(localized(
                    "summary.failuresMore",
                    defaultValue: "…and \(failures.count - 5) more."
                ))
            }
            lines.append("")
            lines.append(localized(
                "summary.fullDiskAccessHint",
                defaultValue: "If access was denied, grant Reclaim Full Disk Access in System Settings → Privacy & Security."
            ))
        }

        return lines.joined(separator: "\n")
    }
}
