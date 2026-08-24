//
//  DoneView+Header.swift
//  Reclaim
//
//  The checkmark, the reclaimed-bytes headline, and the status note
//  beneath it — the top of the post-clean summary.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension DoneView {
    // MARK: - Pieces

    var checkmark: some View {
        let tint = nothingCleaned ? Theme.caution : Theme.safe
        return Image(systemName: summary.isDryRun
            ? "eye"
            : (nothingCleaned ? "exclamationmark.triangle" : "checkmark"))
            .themeFont(.resultIcon)
            .foregroundStyle(nothingCleaned ? Theme.cautionTitle : Theme.accentSoft)
            .frame(width: 58, height: 58)
            .background(tint.opacity(0.16), in: Circle())
            .overlay {
                Circle().strokeBorder(tint.opacity(0.4), lineWidth: 1)
            }
            .scaleEffect(reduceMotion ? 1 : (appeared ? 1 : 0.4))
            .opacity(appeared ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.6), value: appeared)
            .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : appeared)
    }

    var headline: some View {
        VStack(spacing: Theme.Space.s8) {
            if nothingCleaned {
                Text(localized("done.nothingCleanedTitle", defaultValue: "Nothing was cleaned"))
                    .themeFont(.resultHeadline)
                    .foregroundStyle(Theme.textPrimary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s7) {
                    Text(shownBytes.byteParts.value)
                        .font(Theme.heroNumber(44))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText(value: Double(shownBytes)))
                    Text(summary.isDryRun
                        ? localized(
                            "done.unitWouldBeReclaimed",
                            defaultValue: "\(summary.reclaimedBytes.byteParts.unit) would be reclaimed"
                        )
                        : localized(
                            "done.unitReclaimed",
                            defaultValue: "\(summary.reclaimedBytes.byteParts.unit) reclaimed"
                        ))
                        .themeFont(.heroUnit)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text(note)
                .themeFont(.cardTitle)
                .fontWeight(.regular)
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.opacity)
                .animation(Theme.quick, value: note)
        }
        .padding(.top, Theme.Space.s22)
        .entrance(appeared, delay: 0.1)
    }

    private var note: String {
        if summary.isDryRun {
            return localized(
                "done.noteDryRun",
                defaultValue: "Dry run — nothing was touched. Turn off Dry run in Settings to clean for real."
            )
        }
        if summary.wasStopped {
            return localized(
                "done.noteStopped",
                defaultValue: "Stopped early — not every selected item was processed."
            )
        }
        if nothingCleaned {
            return localized(
                "done.noteNothingCleaned",
                defaultValue: "No items could be removed — the failures below explain why."
            )
        }
        switch summary.disposal {
        case .trash:
            return trashState == .emptied
                ? localized(
                    "done.noteTrashEmptied",
                    defaultValue: "Trash emptied. The space is available now."
                )
                : localized(
                    "done.noteMovedToTrash",
                    defaultValue: "Moved to the Trash. Empty it to release the space for good."
                )
        case .delete:
            return localized(
                "done.noteDeleted",
                defaultValue: "Deleted permanently. The space is available now."
            )
        }
    }
}
