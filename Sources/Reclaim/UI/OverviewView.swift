//
//  OverviewView.swift
//  Reclaim
//
//  The post-scan dashboard: the reclaimable ring, real disk usage,
//  category cards, the biggest single locations, tool-managed items
//  that need the user's attention, and lifetime statistics.
//

import AppKit
import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    /// Jumps to a category browser.
    let openCategory: (ToolCategory) -> Void
    /// Selects everything safe and opens the confirmation.
    let reclaimSafe: () -> Void

    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.cardGap) {
                if model.hasFullDiskAccess == false {
                    FullDiskAccessBanner()
                        .entrance(appeared, delay: 0)
                }
                if !model.lastScanWasComplete {
                    partialScanNotice
                        .entrance(appeared, delay: 0)
                }

                HStack(spacing: Theme.cardGap) {
                    reclaimableCard
                        .frame(maxWidth: .infinity)
                        .entrance(appeared, delay: 0.03)
                    diskCard
                        .frame(width: 350)
                        .entrance(appeared, delay: 0.08)
                }
                .fixedSize(horizontal: false, vertical: true)

                categoryGrid
                    .entrance(appeared, delay: 0.13)

                HStack(alignment: .top, spacing: Theme.cardGap) {
                    biggestCard
                        .frame(maxWidth: .infinity)
                        .entrance(appeared, delay: 0.18)
                    VStack(spacing: 12) {
                        if !model.manualTargets.isEmpty {
                            attentionCard
                        }
                        statTiles
                    }
                    .frame(width: 350)
                    .entrance(appeared, delay: 0.22)
                }
            }
            .padding(.horizontal, Theme.contentMargin)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .onAppear { withAnimation(Theme.springy) { appeared = true } }
    }

    // MARK: - Notices

    private var partialScanNotice: some View {
        Label(
            "Scan stopped early — the sizes below cover only what was measured before stopping.",
            systemImage: "exclamationmark.circle"
        )
        .font(Theme.body)
        .foregroundStyle(Theme.cautionTitle)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.caution.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusInset))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusInset)
                .strokeBorder(Theme.caution.opacity(0.3), lineWidth: 0.5)
        }
    }

    // MARK: - Reclaimable card

    private var reclaimableCard: some View {
        HStack(spacing: 22) {
            ring

            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Reclaimable now")

                VStack(alignment: .leading, spacing: 9) {
                    breakdownRow(
                        color: Theme.safe,
                        title: "\(model.safeReclaimableBytes.formattedBytesCompact) safe to remove",
                        subtitle: "^[\(model.safeReclaimableCount) safe item](inflect: true), regenerated automatically"
                    )
                    breakdownRow(
                        color: Theme.cautionBright,
                        title: "\(model.reviewBytes.formattedBytesCompact) needs a decision",
                        subtitle: "^[\(model.reviewCount) item](inflect: true) worth a look first"
                    )
                }
                .padding(.top, 13)

                HStack(spacing: 9) {
                    Button("Reclaim safe space", action: reclaimSafe)
                        .buttonStyle(.rcPrimary)
                        .disabled(model.safeReclaimableBytes == 0)
                    Button("Review everything") {
                        openCategory(largestCategory)
                    }
                    .buttonStyle(.rcSecondary)
                }
                .padding(.top, 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.cardPadding)
        .card()
    }

    private var ring: some View {
        SegmentedRing(segments: ringSegments)
            .frame(width: 136, height: 136)
            .overlay {
                VStack(spacing: 1) {
                    Text(model.totalFoundBytes.byteParts.value)
                        .font(Theme.heroNumber(25))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                        .animation(Theme.smooth, value: model.totalFoundBytes)
                    Text(model.totalFoundBytes.byteParts.unit)
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(Theme.textLabel)
                }
            }
    }

    private var ringSegments: [MeterSegment] {
        let totals = model.categoryTotals()
        let sum = max(1, totals.reduce(Int64(0)) { $0 + $1.bytes })
        return totals.map {
            MeterSegment(
                id: $0.category.id,
                fraction: Double($0.bytes) / Double(sum),
                color: $0.category.color
            )
        }
    }

    private var largestCategory: ToolCategory {
        model.categoryTotals().max { $0.bytes < $1.bytes }?.category ?? .xcode
    }

    private func breakdownRow(color: Color, title: String, subtitle: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(Theme.smooth, value: title)
                Text(subtitle)
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.textLabel)
            }
        }
    }

    // MARK: - Disk card

    private var diskCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel("Macintosh HD")
                Spacer()
                if let space = model.volumeSpace {
                    Text("\(space.usedBytes.wholeGB) used of \(space.totalBytes.wholeGB)")
                        .font(Theme.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(freeGBNumber)
                    .font(Theme.heroNumber(30))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(Theme.smooth, value: freeGBNumber)
                Text("GB free")
                    .font(Theme.cardTitle)
                    .fontWeight(.regular)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 10)

            SegmentedBar(segments: diskSegments, height: 9)
                .padding(.top, 12)

            VStack(spacing: 6) {
                diskLegendRow("Developer caches", model.totalFoundBytes.formattedBytesCompact, Theme.accent)
                diskLegendRow("Other used space", otherUsedBytes.wholeGB, .white.opacity(0.28))
                diskLegendRow("Free", (model.volumeSpace?.availableBytes ?? 0).wholeGB, .white.opacity(0.08))
            }
            .padding(.top, 14)
        }
        .padding(Theme.cardPadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }

    private var freeGBNumber: String {
        guard let space = model.volumeSpace else { return "—" }
        return "\(Int((Double(space.availableBytes) / 1_000_000_000).rounded()))"
    }

    private var otherUsedBytes: Int64 {
        guard let space = model.volumeSpace else { return 0 }
        return max(0, space.usedBytes - model.totalFoundBytes)
    }

    private var diskSegments: [MeterSegment] {
        guard let space = model.volumeSpace, space.totalBytes > 0 else { return [] }
        let total = Double(space.totalBytes)
        return [
            MeterSegment(id: "dev", fraction: Double(model.totalFoundBytes) / total, color: Theme.accent),
            MeterSegment(id: "other", fraction: Double(otherUsedBytes) / total, color: .white.opacity(0.28)),
        ]
    }

    private func diskLegendRow(_ name: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name)
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: 0xB4B4BB))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Color(hex: 0x8E8E95))
        }
    }

    // MARK: - Category grid

    private var categoryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
            spacing: 12
        ) {
            ForEach(ToolCategory.allCases) { category in
                CategoryCard(category: category) {
                    openCategory(category)
                }
            }
        }
    }

    // MARK: - Biggest locations

    private var biggestCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Biggest single locations")
            let largest = model.largestTargets(limit: 6)
            let ceiling = largest.first.map { model.bytes(of: $0) } ?? 0
            VStack(spacing: 0) {
                ForEach(Array(largest.enumerated()), id: \.element.id) { index, target in
                    BiggestRow(
                        rank: index + 1,
                        target: target,
                        fraction: ceiling > 0
                            ? Double(model.bytes(of: target)) / Double(ceiling) : 0
                    ) {
                        openCategory(target.category)
                    }
                }
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 12)
        .padding(.horizontal, Theme.cardPadding)
        .card()
    }

    // MARK: - Attention & stats

    private var attentionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Needs your attention")
            VStack(spacing: 10) {
                ForEach(model.manualTargets) { target in
                    AttentionCard(target: target) {
                        openCategory(target.category)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var statTiles: some View {
        VStack(spacing: 12) {
            StatTile(
                label: "Reclaimed all time",
                sub: model.history.isEmpty
                    ? "no cleans recorded yet"
                    : "across ^[\(model.history.count) clean](inflect: true)",
                value: model.reclaimedAllTimeBytes > 0
                    ? model.reclaimedAllTimeBytes.formattedBytesCompact : "—"
            )
            StatTile(
                label: "Last clean",
                sub: lastCleanSub,
                value: lastCleanValue
            )
            StatTile(
                label: "Next background scan",
                sub: model.weeklyScanEnabled
                    ? "weekly, while Reclaim is running"
                    : "background scans are off",
                value: nextScanValue
            )
        }
    }

    private var lastCleanValue: String {
        guard let last = model.history.first else { return "—" }
        return last.date.formatted(date: .abbreviated, time: .omitted)
    }

    private var lastCleanSub: LocalizedStringKey {
        guard let last = model.history.first else { return "nothing cleaned yet" }
        let freed = last.reclaimedBytes.formattedBytesCompact
        let when = last.date.formatted(.relative(presentation: .named))
        return "\(freed) freed · \(when)"
    }

    private var nextScanValue: String {
        guard model.weeklyScanEnabled else { return "Off" }
        guard let next = model.nextBackgroundScanDate else { return "After first scan" }
        return next.formatted(.dateTime.weekday(.wide).hour().minute())
    }
}

// MARK: - Subviews

/// One tile in the category grid.
private struct CategoryCard: View {
    @Environment(AppModel.self) private var model
    let category: ToolCategory
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        let totals = model.categoryTotals()
        let bytes = totals.first { $0.category == category }?.bytes ?? 0
        let all = totals.reduce(Int64(0)) { $0 + $1.bytes }
        let peak = totals.map(\.bytes).max() ?? 1
        let items = model.targets.count { $0.category == category && model.bytes(of: $0) > 0 }

        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    CategoryTile(category: category)
                    Spacer()
                    Text(all > 0 ? "\(Int((Double(bytes) / Double(all) * 100).rounded()))%" : "—")
                        .font(Theme.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(category.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0xD5D5DB))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 31, alignment: .topLeading)
                    .padding(.top, 11)
                Text(bytes > 0 ? bytes.formattedBytesCompact : "—")
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(Theme.smooth, value: bytes)
                    .padding(.top, 4)
                MiniBar(
                    fraction: peak > 0 ? Double(bytes) / Double(peak) : 0,
                    color: category.color
                )
                .padding(.top, 9)
                Text("^[\(items) item](inflect: true)")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 8)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.white.opacity(isHovered ? 0.07 : 0.04),
                in: RoundedRectangle(cornerRadius: Theme.radiusTile)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusTile)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusTile))
            .scaleEffect(isHovered ? 1.015 : 1)
        }
        .buttonStyle(.plain)
        .animation(Theme.quick, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

/// A ranked row in "Biggest single locations".
private struct BiggestRow: View {
    @Environment(AppModel.self) private var model
    let rank: Int
    let target: CleanupTarget
    let fraction: Double
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(Theme.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textQuaternary)
                    .frame(width: 14, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(target.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Badge(for: target)
                    }
                    Text(target.category.title)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 10)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(model.bytes(of: target).formattedBytesCompact)
                        .font(.system(size: 12.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    MiniBar(fraction: fraction, color: BadgeKind(for: target).color)
                }
                .frame(width: 110)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
        }
        .buttonStyle(.plain)
        .hoverHighlight(color: Color.white.opacity(0.05))
    }
}

/// A "handled by tool" callout with its terminal command.
private struct AttentionCard: View {
    @Environment(AppModel.self) private var model
    let target: CleanupTarget
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(target.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(model.bytes(of: target).formattedBytesCompact)
                        .font(.system(size: 12.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
                Text(target.summary)
                    .font(Theme.footnote)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let command = target.manualCommand {
                    Text(command)
                        .font(Theme.mono())
                        .foregroundStyle(Theme.accentSoft)
                        .padding(.top, 3)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                Color.black.opacity(isHovered ? 0.32 : 0.22),
                in: RoundedRectangle(cornerRadius: Theme.radiusInset)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusInset)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusInset))
        }
        .buttonStyle(.plain)
        .animation(Theme.quick, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

/// One compact statistics tile.
private struct StatTile: View {
    let label: String
    let sub: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                SectionLabel(label)
                Text(sub)
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .card(radius: Theme.radiusTile)
    }
}

/// Full Disk Access warning, restyled for the dark shell.
struct FullDiskAccessBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 16))
                .foregroundStyle(Theme.cautionBright)
            VStack(alignment: .leading, spacing: 2) {
                Text("Full Disk Access is not granted")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("Some locations cannot be measured or cleaned, so results may be incomplete.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button("Open Privacy Settings…") {
                NSWorkspace.shared.open(PrivacyLinks.fullDiskAccess)
            }
            .buttonStyle(.rcSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.caution.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusInset))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusInset)
                .strokeBorder(Theme.caution.opacity(0.3), lineWidth: 0.5)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview(traits: .fixedLayout(width: 1060, height: 900)) {
    OverviewView(openCategory: { _ in }, reclaimSafe: {})
        .background(Theme.background)
        .environment(PreviewData.scanned())
        .preferredColorScheme(.dark)
}
#endif
