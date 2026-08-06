//
//  CleanSummary.swift
//  Reclaim
//
//  Result of one cleanup pass, presented as an alert.
//

import Foundation
import ReclaimKit

/// Aggregated outcome of cleaning the selected targets.
struct CleanSummary: Equatable {
    /// How removals were performed (affects the wording of the alert).
    let disposal: Disposal
    var reclaimedBytes: Int64 = 0
    var cleanedTargets: Int = 0
    /// Human-readable failure lines, empty on full success.
    var failures: [String] = []

    /// Alert body text.
    var message: String {
        var lines: [String] = []

        let space = reclaimedBytes.formattedBytes
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
