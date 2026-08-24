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
        return VStack(alignment: .leading, spacing: Theme.Space.s0) {
            SectionLabel(localized("history.detail.whatWasRemoved", defaultValue: "What was removed"))
                .padding(.bottom, Theme.Space.s4)
            ForEach(items, id: \.targetID) { item in
                let target = results.targets.first { $0.id == item.targetID }
                VStack(alignment: .leading, spacing: Theme.Space.s8) {
                    HStack(spacing: Theme.Space.s10) {
                        if let target {
                            CategoryTile(category: target.category, size: 24)
                        }
                        VStack(alignment: .leading, spacing: Theme.Space.s3) {
                            HStack(spacing: Theme.Space.s7) {
                                Text(item.name)
                                    .themeFont(.rowTitle)
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
                            .themeFont(.amount)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                    }
                    MiniBar(
                        fraction: Double(item.bytesFreed ?? 0) / Double(peak),
                        color: target?.category.color ?? Theme.accent
                    )
                }
                .padding(.vertical, Theme.Space.s9)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.separator).frame(height: 1)
                }
            }
        }
        .padding(.top, Theme.Space.s24)
    }

    /// Entries recorded by earlier versions carry names only.
    @ViewBuilder
    var legacyNames: some View {
        SectionLabel(localized("history.detail.whatWasRemoved", defaultValue: "What was removed"))
            .padding(.top, Theme.Space.s24)
        VStack(alignment: .leading, spacing: Theme.Space.s7) {
            ForEach(entry.targetNames, id: \.self) { name in
                Text(name)
                    .themeFont(.body)
                    .foregroundStyle(Theme.textBody)
            }
        }
        .padding(.top, Theme.Space.s10)
    }
}
