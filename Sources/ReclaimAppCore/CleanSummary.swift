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
    /// How removals were performed (affects the wording of the alert).
    public let disposal: Disposal
    public var reclaimedBytes: Int64 = 0
    public var cleanedTargets: Int = 0
    /// Human-readable failure lines, empty on full success.
    public var failures: [String] = []

    public init(disposal: Disposal) {
        self.disposal = disposal
    }

    /// Alert body text.
    public var message: String {
        var lines: [String] = []

        let space = reclaimedBytes.formatted(.byteCount(style: .file))
        switch disposal {
        case .trash:
            lines.append("Moved \(space) to the Trash from \(cleanedTargets) item(s). Empty the Trash to free the space permanently.")
        case .delete:
            lines.append("Freed \(space) from \(cleanedTargets) item(s).")
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
