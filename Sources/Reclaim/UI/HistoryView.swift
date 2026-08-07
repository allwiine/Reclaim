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
    /// The pass whose detail pane is open, if any.
    @State private var selectedEntryID: UUID?

    var body: some View {
        Group {
            if model.history.isEmpty {
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
                selectedEntryID = model.history.first?.id
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

    private var selectedEntry: CleanHistoryEntry? {
        model.history.first { $0.id == selectedEntryID }
    }

    private var content: some View {
        HStack(spacing: 0) {
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
                HistoryRow(
                    entry: entry,
                    isLast: entry.id == model.history.last?.id,
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

// MARK: - Row

private struct HistoryRow: View {
    let entry: CleanHistoryEntry
    let isLast: Bool
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
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

// MARK: - Detail panel

/// The right-hand pane for one selected clean pass: what it freed, how,
/// what exactly was removed, and how much has grown back since.
private struct HistoryDetailPanel: View {
    @Environment(AppModel.self) private var model
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
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
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 16)
    }

    // MARK: Disposal

    @ViewBuilder
    private func disposalLine(_ disposal: Disposal) -> some View {
        let permanent = disposal == .delete
        let color = permanent ? Theme.destructive : Theme.accentSoft

        HStack(spacing: 8) {
            Text(permanent
                ? localized("history.detail.deletedPermanently", defaultValue: "Deleted permanently")
                : localized("history.detail.movedToTrash", defaultValue: "Moved to Trash"))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .frame(height: 18)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
                }
            Text(metaLine)
                .font(Theme.caption)
                .monospacedDigit()
                .foregroundStyle(Color(hex: 0x8E8E95))
        }
        .padding(.top, 10)

        Text(trashNote(disposal))
            .font(Theme.caption)
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

    private func diskAfter(_ freeAfter: Int64) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(localized("history.detail.diskAfter", defaultValue: "Disk after"))
                Spacer(minLength: 8)
                Text(localized(
                    "history.detail.freeAfterLabel",
                    defaultValue: "\(freeAfter.wholeGB) free after this clean"
                ))
                .font(Theme.caption)
                .monospacedDigit()
                .foregroundStyle(Color(hex: 0x8E8E95))
            }
            if let total = model.volumeSpace?.totalBytes, total > 0 {
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

    // MARK: What was removed

    private func removedList(_ items: [CleanedHistoryItem]) -> some View {
        let peak = max(items.compactMap(\.bytesFreed).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel(localized("history.detail.whatWasRemoved", defaultValue: "What was removed"))
                .padding(.bottom, 4)
            ForEach(items, id: \.targetID) { item in
                let target = model.targets.first { $0.id == item.targetID }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        if let target {
                            CategoryTile(category: target.category, size: 24)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .medium))
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
                            .font(.system(size: 12.5, weight: .medium))
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
    private var legacyNames: some View {
        SectionLabel(localized("history.detail.whatWasRemoved", defaultValue: "What was removed"))
            .padding(.top, 24)
        VStack(alignment: .leading, spacing: 7) {
            ForEach(entry.targetNames, id: \.self) { name in
                Text(name)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textBody)
            }
        }
        .padding(.top, 10)
    }

    // MARK: Since then

    @ViewBuilder
    private func regrowth(_ items: [CleanedHistoryItem]) -> some View {
        SectionLabel(localized("history.detail.sinceThen", defaultValue: "Since then"))
            .padding(.top, 24)
        VStack(alignment: .leading, spacing: 7) {
            ForEach(items, id: \.targetID) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(item.name)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textBody)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(regrowthLabel(for: item))
                        .font(Theme.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: 0x8E8E95))
                    Text(regrowthShare(for: item))
                        .font(Theme.footnote)
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
        .font(Theme.caption)
        .lineSpacing(2.5)
        .foregroundStyle(Theme.textQuaternary)
        .padding(.top, 12)
    }

    /// Today's measured size of the target, when a scan can tell.
    private func currentBytes(for item: CleanedHistoryItem) -> Int64? {
        guard let target = model.targets.first(where: { $0.id == item.targetID }),
              case .measured(let measurement, _, _) = model.status(of: target.id)
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
