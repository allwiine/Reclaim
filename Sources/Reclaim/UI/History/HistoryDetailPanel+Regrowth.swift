//
//  HistoryDetailPanel+Regrowth.swift
//  Reclaim
//
//  The history detail pane's "Since then" section: how much of what a
//  pass removed has grown back, measured against the following scan.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension HistoryDetailPanel {
    // MARK: Since then

    @ViewBuilder
    func regrowth(_ items: [CleanedHistoryItem]) -> some View {
        SectionLabel(localized("history.detail.sinceThen", defaultValue: "Since then"))
            .padding(.top, 24)
        VStack(alignment: .leading, spacing: 7) {
            ForEach(items, id: \.targetID) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(item.name)
                        .scaledFont(size: 12)
                        .foregroundStyle(Theme.textBody)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(regrowthLabel(for: item))
                        .themeFont(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: 0x8E8E95))
                    Text(regrowthShare(for: item))
                        .themeFont(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textQuaternary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .padding(.top, 10)
        Text(localized(
            "history.detail.regrowthFootnote",
            defaultValue: "Caches rebuild as you work. The percentage is today's size measured against what this clean removed."
        ))
        .themeFont(.caption)
        .lineSpacing(2.5)
        .foregroundStyle(Theme.textQuaternary)
        .padding(.top, 12)
    }

    /// Today's measured size of the target, when a scan can tell.
    private func currentBytes(for item: CleanedHistoryItem) -> Int64? {
        guard let target = model.results.targets.first(where: { $0.id == item.targetID }),
              case .measured(let measurement, _, _) = model.results.status(of: target.id)
        else { return nil }
        return measurement.bytes
    }

    /// Growth since the pass. Judged against the size the rescan saw
    /// right afterwards — what a cherry-picked clean left behind was
    /// never removed and must not count as regrowth. Entries recorded
    /// before `bytesAfter` existed fall back to a zero baseline.
    private func regrownBytes(for item: CleanedHistoryItem) -> Int64? {
        guard let current = currentBytes(for: item) else { return nil }
        return max(0, current - (item.bytesAfter ?? 0))
    }

    private func regrowthLabel(for item: CleanedHistoryItem) -> String {
        guard let regrown = regrownBytes(for: item) else {
            return localized("accessibility.notMeasuredYet", defaultValue: "Not measured yet")
        }
        guard regrown > 0 else {
            return localized("history.detail.stillClean", defaultValue: "still clean")
        }
        return localized(
            "history.detail.againNow",
            defaultValue: "\(regrown.formattedBytesCompact) again now"
        )
    }

    private func regrowthShare(for item: CleanedHistoryItem) -> String {
        guard let regrown = regrownBytes(for: item), regrown > 0,
              let freed = item.bytesFreed, freed > 0
        else { return "—" }
        return (Double(regrown) / Double(freed))
            .formatted(.percent.precision(.fractionLength(0)))
    }
}
