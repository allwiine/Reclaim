//
//  HistoryView.swift
//  Reclaim
//
//  Past clean passes: the lifetime total, a small trend chart, and
//  the full table.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var appeared = false
    @State private var isConfirmingClear = false

    var body: some View {
        Group {
            if model.history.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .onAppear { withAnimation(Theme.springy) { appeared = true } }
        .confirmationDialog(
            localized("history.clearConfirmTitle", defaultValue: "Clear all clean history?"),
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button(
                localized("history.clearConfirmAction", defaultValue: "Clear History"),
                role: .destructive
            ) {
                model.clearHistory()
            }
        } message: {
            Text(localized(
                "history.clearConfirmMessage",
                defaultValue: "Removes the record of every clean pass and resets the lifetime statistics. No files on disk are affected."
            ))
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(Theme.textQuaternary)
            Text(localized("history.emptyTitle", defaultValue: "No cleans yet"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text(localized(
                "history.emptyDetail",
                defaultValue: "Every clean pass is recorded here: when it ran, what it covered, and how much space came back."
            ))
            .font(Theme.body)
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(localized("overview.reclaimedAllTime", defaultValue: "Reclaimed all time"))
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(model.reclaimedAllTimeBytes.byteParts.value)
                                .font(Theme.heroNumber(34))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                                .contentTransition(.numericText())
                            Text(model.reclaimedAllTimeBytes.byteParts.unit)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    chart
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                }
                .entrance(appeared, delay: 0)

                table
                    .padding(.top, 28)
                    .entrance(appeared, delay: 0.08)

                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(localized(
                        "history.footnote",
                        defaultValue: "Each entry lists what was cleaned and what the follow-up scan measured as actually freed."
                    ))
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.textQuaternary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(localized("history.clearButton", defaultValue: "Clear History…")) {
                        isConfirmingClear = true
                    }
                    .buttonStyle(.rcSecondary)
                }
                .padding(.top, 14)
                .entrance(appeared, delay: 0.12)
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)
            .padding(.bottom, 40)
        }
    }

    /// Oldest → newest bars, opacity scaled by size like the design.
    private var chart: some View {
        let entries = Array(model.history.reversed().suffix(24))
        let peak = max(1, entries.map(\.reclaimedBytes).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let share = Double(entry.reclaimedBytes) / Double(peak)
                UnevenRoundedRectangle(
                    topLeadingRadius: 3, bottomLeadingRadius: 2,
                    bottomTrailingRadius: 2, topTrailingRadius: 3
                )
                .fill(Theme.accent.opacity(0.35 + share * 0.55))
                .frame(maxWidth: .infinity)
                .frame(height: appeared ? max(8, share * 72) : 8)
                .animation(Theme.springy.delay(Double(index) * 0.03), value: appeared)
                .help(localized(
                    "history.chartHelp",
                    defaultValue: "\(entry.date.formatted(date: .abbreviated, time: .shortened)) — \(entry.reclaimedBytes.formattedBytesCompact)"
                ))
            }
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                headerCell(localized("history.columnWhen", defaultValue: "When"), width: 150)
                Text(localized("history.columnWhat", defaultValue: "What"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                headerCell(localized("history.columnItems", defaultValue: "Items"), width: 80, trailing: true)
                headerCell(localized("history.columnFreed", defaultValue: "Freed"), width: 90, trailing: true)
            }
            .font(Theme.labelFont)
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }

            ForEach(model.history) { entry in
                HistoryRow(entry: entry, isLast: entry.id == model.history.last?.id)
            }
        }
        .card(radius: Theme.radiusPanel, fill: Theme.cardFillQuiet)
    }

    private func headerCell(_ text: String, width: CGFloat, trailing: Bool = false) -> some View {
        Text(text)
            .frame(width: width, alignment: trailing ? .trailing : .leading)
    }
}

// MARK: - Row

private struct HistoryRow: View {
    let entry: CleanHistoryEntry
    let isLast: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                .font(Theme.body)
                .monospacedDigit()
                .foregroundStyle(Color(hex: 0xC8C8CF))
                .frame(width: 150, alignment: .leading)
            Text(entry.targetNames.joined(separator: ", "))
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                // The single line truncates long passes; the tooltip
                // always carries the full list.
                .help(entry.targetNames.joined(separator: ", "))
            Text(entry.itemsRemoved.formatted())
                .font(Theme.body)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 80, alignment: .trailing)
            Text(entry.reclaimedBytes.formattedBytesCompact)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isHovered ? Color.white.opacity(0.04) : .clear)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Theme.separator).frame(height: 1)
            }
        }
        .animation(Theme.quick, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("With history", traits: .fixedLayout(width: 1060, height: 810)) {
    HistoryView()
        .background(Theme.background)
        .environment(PreviewData.scanned())
        .preferredColorScheme(.dark)
}

#Preview("Empty", traits: .fixedLayout(width: 1060, height: 810)) {
    HistoryView()
        .background(Theme.background)
        .environment(PreviewData.idle())
        .preferredColorScheme(.dark)
}
#endif
