//
//  HistoryDetailPanel+Disposal.swift
//  Reclaim
//
//  The history detail pane's disposal line (Trash vs. permanent
//  delete, with its meta line and note) and the "disk after" gauge.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension HistoryDetailPanel {
    // MARK: Disposal

    @ViewBuilder
    func disposalLine(_ disposal: Disposal) -> some View {
        let permanent = disposal == .delete
        let color = permanent ? Theme.destructive : Theme.accentSoft

        HStack(spacing: 8) {
            Text(permanent
                ? localized("history.detail.deletedPermanently", defaultValue: "Deleted permanently")
                : localized("history.detail.movedToTrash", defaultValue: "Moved to Trash"))
                .scaledFont(size: 10.5, weight: .semibold)
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .frame(height: 18)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
                }
            Text(metaLine)
                .themeFont(.caption)
                .monospacedDigit()
                .foregroundStyle(Color(hex: 0x8E8E95))
        }
        .padding(.top, 10)

        Text(trashNote(disposal))
            .themeFont(.caption)
            .lineSpacing(2.5)
            .foregroundStyle(Theme.textLabel)
            .padding(.top, 9)
    }

    private var metaLine: String {
        let locations = localized(
            "count.locations",
            defaultValue: "\(entry.targetNames.count) locations"
        )
        guard let duration = entry.duration else { return locations }
        // Small passes finish in well under a second; whole-second
        // formatting would claim "0 s". Show a decimal below a minute,
        // clamped to a decisecond so the label never reads as zero.
        let time: String =
            if duration < 60 {
                Duration.seconds(max(duration, 0.1)).formatted(
                    .units(allowed: [.seconds], width: .narrow, fractionalPart: .show(length: 1))
                )
            } else {
                Duration.seconds(duration)
                    .formatted(.units(allowed: [.minutes, .seconds], width: .narrow))
            }
        return localized("history.detail.metaLine", defaultValue: "\(locations) · \(time)")
    }

    private func trashNote(_ disposal: Disposal) -> String {
        if disposal == .delete {
            return localized(
                "history.detail.permanentNote",
                defaultValue: "Removed immediately; not recoverable."
            )
        }
        if let emptied = entry.trashEmptiedDate {
            let when = emptied.formatted(date: .abbreviated, time: .shortened)
            return localized(
                "history.detail.trashEmptiedNote",
                defaultValue: "Trash emptied \(when)."
            )
        }
        // Whether the Trash was emptied outside Reclaim is unknowable,
        // so this stays conditional — never "still in the Trash".
        return localized(
            "history.detail.trashUnknownNote",
            defaultValue: "Moved to the Trash — if you haven't emptied it since, the files can still be put back."
        )
    }

    // MARK: Disk after

    func diskAfter(_ freeAfter: Int64) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(localized("history.detail.diskAfter", defaultValue: "Disk after"))
                Spacer(minLength: 8)
                Text(localized(
                    "history.detail.freeAfterLabel",
                    defaultValue: "\(freeAfter.wholeGB) free after this clean"
                ))
                .themeFont(.caption)
                .monospacedDigit()
                .foregroundStyle(Color(hex: 0x8E8E95))
            }
            if let total = model.results.volumeSpace?.totalBytes, total > 0 {
                ProgressBar(fraction: Double(freeAfter) / Double(total), height: 6)
                    .padding(.top, 9)
            }
        }
        .padding(.top, 20)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 1).offset(y: 10)
        }
        .padding(.top, 10)
    }
}
