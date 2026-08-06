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

    /// Alert body text.
    public var message: String {
        var lines: [String] = []

        if isDryRun {
            let space = reclaimedBytes.formatted(.byteCount(style: .file))
            lines.append("Dry run — nothing was touched. Cleaning this selection would free about \(space).")
            return lines.joined(separator: "\n")
        }

        if wasStopped {
            lines.append("Cleaning was stopped early — not every selected item was processed.")
        }

        if itemsRemoved == 0 {
            lines.append("Nothing was cleaned.")
        } else {
            let space = reclaimedBytes.formatted(.byteCount(style: .file))
            // Automatic grammar agreement keeps "1 item" / "3 items"
            // correct without manual pluralization. AttributedString
            // (not String(localized:)) processes the inflection even
            // without a strings catalog.
            let items = String(AttributedString(
                localized: "^[\(itemsRemoved) item](inflect: true)"
            ).characters)
            let locations = String(AttributedString(
                localized: "^[\(cleanedTargets) location](inflect: true)"
            ).characters)
            switch disposal {
            case .trash:
                lines.append("Moved \(items) (\(space)) from \(locations) to the Trash. Empty the Trash to free the space permanently.")
            case .delete:
                lines.append("Freed \(space) by permanently deleting \(items) from \(locations).")
            }
        }

        if !failures.isEmpty {
            lines.append("")
            lines.append("Some items could not be cleaned:")
            lines.append(contentsOf: failures.prefix(5))
            if failures.count > 5 {
                lines.append("…and \(failures.count - 5) more.")
            }
            lines.append("")
            lines.append("If access was denied, grant Reclaim Full Disk Access in System Settings → Privacy & Security.")
        }

        return lines.joined(separator: "\n")
    }
}
