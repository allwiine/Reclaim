//
//  HistoryDetailPanel.swift
//  Reclaim
//
//  The right-hand pane for one selected clean pass: what it freed, how,
//  what exactly was removed, and how much has grown back since.
//

import ReclaimAppCore
import SwiftUI

/// The right-hand pane for one selected clean pass: what it freed, how,
/// what exactly was removed, and how much has grown back since.
struct HistoryDetailPanel: View {
    @Environment(TargetResultsModel.self) var results
    let entry: CleanHistoryEntry
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                hero
                if let disposal = entry.disposal {
                    disposalLine(disposal)
                }
                if let freeAfter = entry.freeAfterBytes {
                    diskAfter(freeAfter)
                }
                if let items = entry.items, !items.isEmpty {
                    removedList(items)
                    regrowth(items)
                } else {
                    legacyNames
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white.opacity(0.02))
        .id(entry.id)
    }

    // MARK: Header & hero

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                SectionLabel(localized("history.detail.trigger", defaultValue: "Manual clean"))
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: close) {
                Image(systemName: "xmark")
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(Theme.textBody)
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help(localized("action.close", defaultValue: "Close"))
        }
    }

    private var hero: some View {
        let parts = entry.reclaimedBytes.byteParts
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(parts.value)
                .font(Theme.heroNumber(30))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(localized("history.detail.unitFreed", defaultValue: "\(parts.unit) freed"))
                .scaledFont(size: 14)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 16)
    }
}
