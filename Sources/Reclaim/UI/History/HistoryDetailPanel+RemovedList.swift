//
//  HistoryDetailPanel+RemovedList.swift
//  Reclaim
//
//  The history detail pane's "what was removed" list, plus the
//  names-only fallback for entries recorded before item detail existed.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension HistoryDetailPanel {
    // MARK: What was removed

    func removedList(_ items: [CleanedHistoryItem]) -> some View {
        let peak = max(items.compactMap(\.bytesFreed).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel(localized("history.detail.whatWasRemoved", defaultValue: "What was removed"))
                .padding(.bottom, 4)
            ForEach(items, id: \.targetID) { item in
                let target = model.results.targets.first { $0.id == item.targetID }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        if let target {
                            CategoryTile(category: target.category, size: 24)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(item.name)
                                    .scaledFont(size: 13, weight: .medium)
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                if let target {
                                    Badge(for: target)
                                }
                            }
                            if let path = target?.pathPatterns.first {
                                Text(path)
                                    .font(Theme.mono(10.5))
                                    .foregroundStyle(Theme.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(item.bytesFreed.map(\.formattedBytesCompact)
                            ?? localized("confirm.sizeUnknown", defaultValue: "size unknown"))
                            .scaledFont(size: 12.5, weight: .medium)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                    }
                    MiniBar(
                        fraction: Double(item.bytesFreed ?? 0) / Double(peak),
                        color: target?.category.color ?? Theme.accent
                    )
                }
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.separator).frame(height: 1)
                }
            }
        }
        .padding(.top, 24)
    }

    /// Entries recorded by earlier versions carry names only.
    @ViewBuilder
    var legacyNames: some View {
        SectionLabel(localized("history.detail.whatWasRemoved", defaultValue: "What was removed"))
            .padding(.top, 24)
        VStack(alignment: .leading, spacing: 7) {
            ForEach(entry.targetNames, id: \.self) { name in
                Text(name)
                    .themeFont(.body)
                    .foregroundStyle(Theme.textBody)
            }
        }
        .padding(.top, 10)
    }
}
