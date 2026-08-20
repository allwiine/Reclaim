//
//  HistoryRow.swift
//  Reclaim
//
//  One row in the history table.
//

import ReclaimAppCore
import SwiftUI

struct HistoryRow: View {
    let entry: CleanHistoryEntry
    let isLast: Bool
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 14) {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .themeFont(.body)
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: 0xC8C8CF))
                    .frame(width: 150, alignment: .leading)
                Text(entry.targetNames.joined(separator: ", "))
                    .themeFont(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The single line truncates long passes; the tooltip
                    // always carries the full list.
                    .help(entry.targetNames.joined(separator: ", "))
                Text(entry.itemsRemoved.formatted())
                    .themeFont(.body)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 80, alignment: .trailing)
                Text(entry.reclaimedBytes.formattedBytesCompact)
                    .scaledFont(size: 13, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 90, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                isSelected ? Color.white.opacity(0.06)
                    : isHovered ? Color.white.opacity(0.04) : .clear
            )
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle().fill(Theme.separator).frame(height: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.quick, value: isHovered)
        .animation(Theme.quick, value: isSelected)
        .onHover { isHovered = $0 }
    }
}
