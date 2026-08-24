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
    @Environment(HistoryModel.self) private var history
    @State private var appeared = false
    @State private var isConfirmingClear = false
    /// The pass whose detail pane is open, if any.
    @State private var selectedEntryID: UUID?

    var body: some View {
        Group {
            if history.entries.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .onAppear { withAnimation(Theme.springy) { appeared = true } }
        #if DEBUG
        // Smoke-test hook: opens the newest pass's detail pane, since
        // clicks cannot be scripted without Accessibility permission.
        .task {
            if ProcessInfo.processInfo.arguments.contains("--select-first-clean") {
                selectedEntryID = history.entries.first?.id
            }
        }
        #endif
        .confirmationDialog(
            localized("history.clearConfirmTitle", defaultValue: "Clear all clean history?"),
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button(
                localized("history.clearConfirmAction", defaultValue: "Clear History"),
                role: .destructive
            ) {
                history.clear()
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
        VStack(spacing: Theme.Space.s10) {
            Image(systemName: "clock.arrow.circlepath")
                .themeFont(.emptyStateIcon)
                .foregroundStyle(Theme.textQuaternary)
            Text(localized("history.emptyTitle", defaultValue: "No cleans yet"))
                .themeFont(.emptyStateTitle)
                .foregroundStyle(Theme.textSecondary)
            Text(localized(
                "history.emptyDetail",
                defaultValue: "Every clean pass is recorded here: when it ran, what it covered, and how much space came back."
            ))
            .themeFont(.body)
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    private var selectedEntry: CleanHistoryEntry? {
        history.entries.first { $0.id == selectedEntryID }
    }

    private var content: some View {
        HStack(spacing: Theme.Space.s0) {
            list
                .frame(maxWidth: .infinity)

            if let entry = selectedEntry {
                Rectangle()
                    .fill(Theme.divider)
                    .frame(width: 1)
                HistoryDetailPanel(entry: entry) {
                    selectedEntryID = nil
                }
                .frame(width: 352)
            }
        }
        .animation(Theme.quick, value: selectedEntryID == nil)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s0) {
                HStack(alignment: .bottom, spacing: Theme.Space.s24) {
                    VStack(alignment: .leading, spacing: Theme.Space.s6) {
                        SectionLabel(localized("overview.reclaimedAllTime", defaultValue: "Reclaimed (all time)"))
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s6) {
                            Text(history.reclaimedAllTimeBytes.byteParts.value)
                                .font(Theme.heroNumber(34))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                                .contentTransition(.numericText())
                            Text(history.reclaimedAllTimeBytes.byteParts.unit)
                                .themeFont(.statUnit)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    chart
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                }
                .entrance(appeared, delay: 0)

                table
                    .padding(.top, Theme.Space.s28)
                    .entrance(appeared, delay: 0.08)

                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s16) {
                    Text(localized(
                        "history.footnote",
                        defaultValue: "Each entry lists what was cleaned and what the follow-up scan measured as actually freed."
                    ))
                    .themeFont(.footnote)
                    .foregroundStyle(Theme.textQuaternary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(localized("history.clearButton", defaultValue: "Clear History…")) {
                        isConfirmingClear = true
                    }
                    .rcSecondary()
                }
                .padding(.top, Theme.Space.s14)
                .entrance(appeared, delay: 0.12)
            }
            .padding(.horizontal, Theme.Space.s26)
            .padding(.top, Theme.Space.s22)
            .padding(.bottom, Theme.Space.s40)
        }
    }

    /// Oldest → newest bars, opacity scaled by size like the design.
    private var chart: some View {
        let entries = Array(history.entries.reversed().suffix(24))
        let peak = max(1, entries.map(\.reclaimedBytes).max() ?? 1)
        return HStack(alignment: .bottom, spacing: Theme.Space.s6) {
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
        VStack(spacing: Theme.Space.s0) {
            HStack(spacing: Theme.Space.s14) {
                headerCell(localized("history.columnWhen", defaultValue: "When"), width: 150)
                Text(localized("history.columnWhat", defaultValue: "What"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                headerCell(localized("history.columnItems", defaultValue: "Items"), width: 80, trailing: true)
                headerCell(localized("history.columnFreed", defaultValue: "Freed"), width: 90, trailing: true)
            }
            .themeFont(.label)
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, Theme.Space.s16)
            .padding(.vertical, Theme.Space.s9)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.dividerStrong).frame(height: 1)
            }

            ForEach(history.entries) { entry in
                HistoryRow(
                    entry: entry,
                    isLast: entry.id == history.entries.last?.id,
                    isSelected: entry.id == selectedEntryID
                ) {
                    selectedEntryID = entry.id
                }
            }
        }
        .card(radius: Theme.radiusPanel, fill: Theme.cardFillQuiet)
    }

    private func headerCell(_ text: String, width: CGFloat, trailing: Bool = false) -> some View {
        Text(text)
            .frame(width: width, alignment: trailing ? .trailing : .leading)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("With history", traits: .fixedLayout(width: 1060, height: 810)) {
    HistoryView()
        .background(Theme.background)
        .appEnvironment(PreviewData.scanned())
        .preferredColorScheme(.dark)
}

#Preview("Empty", traits: .fixedLayout(width: 1060, height: 810)) {
    HistoryView()
        .background(Theme.background)
        .appEnvironment(PreviewData.idle())
        .preferredColorScheme(.dark)
}
#endif
