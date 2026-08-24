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
            VStack(alignment: .leading, spacing: Theme.Space.s0) {
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
            .padding(.horizontal, Theme.Space.s20)
            .padding(.top, Theme.Space.s18)
            .padding(.bottom, Theme.Space.s28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.chromeFill)
        .id(entry.id)
    }

    // MARK: Header & hero

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Space.s12) {
            VStack(alignment: .leading, spacing: Theme.Space.s5) {
                SectionLabel(localized("history.detail.trigger", defaultValue: "Manual clean"))
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .themeFont(.detailHeaderTitle)
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: close) {
                Image(systemName: "xmark")
                    .themeFont(.disclosure)
                    .foregroundStyle(Theme.textBody)
                    .frame(width: 22, height: 22)
                    .background(Theme.controlFillQuiet, in: RoundedRectangle(cornerRadius: Theme.radiusIconChip))
                    .contentShape(RoundedRectangle(cornerRadius: Theme.radiusIconChip))
            }
            .buttonStyle(.plain)
            .help(localized("action.close", defaultValue: "Close"))
        }
    }

    private var hero: some View {
        let parts = entry.reclaimedBytes.byteParts
        return HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s6) {
            Text(parts.value)
                .font(Theme.heroNumber(30))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(localized("history.detail.unitFreed", defaultValue: "\(parts.unit) freed"))
                .themeFont(.detailHeroUnit)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, Theme.Space.s16)
    }
}
