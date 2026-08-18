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
    /// Jumps to a specific target's row in its category browser.
    let openTarget: (CleanupTarget) -> Void
    /// Opens the cross-category "all findings" browser.
    let reviewEverything: () -> Void
    /// Selects everything safe and opens the confirmation.
    let reclaimSafe: () -> Void
    /// Opens the dev-folder Projects screen.
    let openProjects: () -> Void

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
                    // Lifetime/last/next stats live in the global footer;
                    // the column only appears when it has cards to show.
                    if !model.devRoots.isEmpty || !model.manualTargets.isEmpty {
                        VStack(spacing: 12) {
                            if !model.devRoots.isEmpty {
                                projectsCard
                            }
                            if !model.manualTargets.isEmpty {
                                attentionCard
                            }
                        }
                        .frame(width: 350)
                        .entrance(appeared, delay: 0.22)
                    }
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
            localized(
                "overview.partialScanNotice",
                defaultValue: "Scan stopped early — the sizes below cover only what was measured before stopping."
            ),
            systemImage: "exclamationmark.circle"
        )
        .themeFont(.body)
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
                // "Found", not "reclaimable": the ring's total includes
                // tool-managed items Reclaim measures but never deletes.
                SectionLabel(localized("overview.foundOnThisMac", defaultValue: "Found on this Mac"))

                VStack(alignment: .leading, spacing: 9) {
                    // After a clean pass the safe bucket is often empty;
                    // saying so beats formatting 0 bytes as "< 1 MB" and
                    // offering a button that cannot do anything.
                    if model.safeReclaimableBytes > 0 {
                        breakdownRow(
                            color: Theme.safe,
                            title: localized(
                                "overview.safeToRemove",
                                defaultValue: "\(model.safeReclaimableBytes.formattedBytesCompact) safe to remove"
                            ),
                            subtitle: localized(
                                "overview.safeItemsSubtitle",
                                defaultValue: "\(model.safeReclaimableCount) safe items, regenerated automatically"
                            )
                        )
                    } else {
                        breakdownRow(
                            color: Theme.safe,
                            title: localized(
                                "overview.nothingSafeLeft",
                                defaultValue: "Nothing safe left to remove"
                            ),
                            subtitle: localized(
                                "overview.nothingSafeLeftSubtitle",
                                defaultValue: "Everything rated Safe is already clean — scan again to re-measure."
                            )
                        )
                    }
                    breakdownRow(
                        color: Theme.cautionBright,
                        title: localized(
                            "overview.needsDecision",
                            defaultValue: "\(model.reviewBytes.formattedBytesCompact) needs a decision"
                        ),
                        subtitle: localized(
                            "overview.reviewItemsSubtitle",
                            defaultValue: "\(model.reviewCount) items worth a look first"
                        )
                    )
                    // Dev-folder artifacts are inside the ring's total, so
                    // the rows only sum up to it with this third slice.
                    if model.projectArtifactBytes > 0 {
                        breakdownRow(
                            color: Theme.accent,
                            title: localized(
                                "overview.projectArtifacts",
                                defaultValue: "\(model.projectArtifactBytes.formattedBytesCompact) in project artifacts"
                            ),
                            subtitle: localized(
                                "overview.projectArtifactsSubtitle",
                                defaultValue: "\(model.projectsWithArtifactsCount) projects, cleaned from the Projects screen"
                            )
                        )
                    }
                }
                .padding(.top, 13)

                HStack(spacing: 9) {
                    if model.safeReclaimableBytes > 0 {
                        Button(
                            localized("overview.reclaimSafeButton", defaultValue: "Reclaim safe space"),
                            action: reclaimSafe
                        )
                        .buttonStyle(.rcPrimary)
                    } else {
                        Button(localized("action.scanAgain", defaultValue: "Scan again")) {
                            model.scanAll()
                        }
                        .buttonStyle(.rcPrimary)
                    }
                    Button(localized("overview.reviewEverythingButton", defaultValue: "Review everything")) {
                        reviewEverything()
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
                        .scaledFont(size: 10.5, weight: .semibold)
                        .tracking(0.7)
                        .foregroundStyle(Theme.textLabel)
                }
            }
    }

    // The center number is `totalFoundBytes`, which counts dev-folder
    // artifacts — the colored composition must cover the same total,
    // so projects get their own segment.
    private var ringSegments: [MeterSegment] {
        let totals = model.categoryTotals()
        let projectBytes = model.projectArtifactBytes
        let sum = max(1, totals.reduce(Int64(0)) { $0 + $1.bytes } + projectBytes)
        var segments = totals.map {
            MeterSegment(
                id: $0.category.id,
                fraction: Double($0.bytes) / Double(sum),
                color: $0.category.color
            )
        }
        if projectBytes > 0 {
            segments.append(MeterSegment(
                id: "projects",
                fraction: Double(projectBytes) / Double(sum),
                color: Theme.accent
            ))
        }
        return segments
    }

    private func breakdownRow(color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .themeFont(.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(Theme.smooth, value: title)
                Text(subtitle)
                    .themeFont(.footnote)
                    .foregroundStyle(Theme.textLabel)
            }
        }
    }

    // MARK: - Disk card

    private var diskCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(model.volumeDisplayName)
                Spacer()
                if let space = model.volumeSpace {
                    Text(localized(
                        "disk.usedOfTotal",
                        defaultValue: "\(space.usedBytes.wholeGB) used of \(space.totalBytes.wholeGB)"
                    ))
                    .themeFont(.footnote)
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
                Text(localized("disk.gbFree", defaultValue: "GB free"))
                    .themeFont(.cardTitle)
                    .fontWeight(.regular)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 10)

            SegmentedBar(segments: diskSegments, height: 9)
                .padding(.top, 12)

            VStack(spacing: 6) {
                diskLegendRow(
                    localized("disk.legendDeveloperCaches", defaultValue: "Developer caches"),
                    model.totalFoundBytes.formattedBytesCompact,
                    Theme.accent
                )
                diskLegendRow(
                    localized("disk.legendOtherUsed", defaultValue: "Other used space"),
                    otherUsedBytes.wholeGB,
                    .white.opacity(0.28)
                )
                diskLegendRow(
                    localized("disk.legendFree", defaultValue: "Free"),
                    (model.volumeSpace?.availableBytes ?? 0).wholeGB,
                    .white.opacity(0.08)
                )
            }
            .padding(.top, 14)
        }
        .padding(Theme.cardPadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }

    private var freeGBNumber: String {
        guard let space = model.volumeSpace else { return "—" }
        return space.availableBytes.wholeGBValue
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
                .scaledFont(size: 12)
                .foregroundStyle(Color(hex: 0xB4B4BB))
            Spacer(minLength: 8)
            Text(value)
                .scaledFont(size: 12)
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
            SectionLabel(localized("overview.biggestLocations", defaultValue: "Biggest single locations"))
            // Registry targets and dev-folder projects, ranked together.
            let largest = model.largestFindings(limit: 6)
            let ceiling = largest.first?.bytes ?? 0
            VStack(spacing: 0) {
                ForEach(Array(largest.enumerated()), id: \.element.id) { index, finding in
                    let fraction = ceiling > 0 ? Double(finding.bytes) / Double(ceiling) : 0
                    switch finding {
                    case .target(let target, _):
                        BiggestRow(rank: index + 1, target: target, fraction: fraction) {
                            openTarget(target)
                        }
                    case .project(let project):
                        ProjectFindingRow(rank: index + 1, project: project, fraction: fraction) {
                            openProjects()
                        }
                    }
                }
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 12)
        .padding(.horizontal, Theme.cardPadding)
        .card()
    }

    // MARK: - Projects card

    /// Compact dev-folder summary: how much the discovered projects'
    /// artifacts hold, and the biggest offenders. Tapping anywhere
    /// opens the Projects screen. Shown only once dev folders exist.
    private var projectsCard: some View {
        Button(action: openProjects) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(localized("sidebar.projects", defaultValue: "Projects"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .scaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(Theme.textQuaternary)
                }
                if model.projects.isEmpty {
                    Text(localized(
                        "projects.noneFound",
                        defaultValue: "No projects found in the added folders."
                    ))
                    .themeFont(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                } else {
                    Text(localized(
                        "toolbar.projectsSubtitle",
                        defaultValue: "\(model.projects.count) projects · \(model.projectArtifactBytes.formattedBytesCompact)"
                    ))
                    .scaledFont(size: 14, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(Theme.smooth, value: model.projectArtifactBytes)

                    VStack(spacing: 6) {
                        ForEach(model.largestProjects(limit: 2)) { project in
                            HStack(spacing: 8) {
                                Image(systemName: "folder.badge.gearshape")
                                    .scaledFont(size: 10.5)
                                    .foregroundStyle(Theme.textTertiary)
                                Text(project.name)
                                    .scaledFont(size: 12)
                                    .foregroundStyle(Color(hex: 0xB4B4BB))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(project.artifactBytes.formattedBytesCompact)
                                    .scaledFont(size: 12)
                                    .monospacedDigit()
                                    .foregroundStyle(Color(hex: 0x8E8E95))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusTile))
        }
        .buttonStyle(.plain)
        .card(radius: Theme.radiusTile)
        .hoverHighlight()
    }

    // MARK: - Attention & stats

    private var attentionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(localized("overview.needsAttention", defaultValue: "Needs your attention"))
            VStack(spacing: 10) {
                ForEach(model.manualTargets) { target in
                    AttentionCard(target: target) {
                        openTarget(target)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
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
        // Share of everything found, dev-folder artifacts included —
        // the same denominator as the overview ring.
        let all = model.totalFoundBytes
        let peak = totals.map(\.bytes).max() ?? 1
        let items = model.targets.count { $0.category == category && model.bytes(of: $0) > 0 }

        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    CategoryTile(category: category)
                    Spacer()
                    Text(all > 0
                        ? (Double(bytes) / Double(all))
                            .formatted(.percent.precision(.fractionLength(0)))
                        : "—")
                        .themeFont(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(category.title)
                    .scaledFont(size: 12, weight: .medium)
                    .foregroundStyle(Color(hex: 0xD5D5DB))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 31, alignment: .topLeading)
                    .padding(.top, 11)
                Text(bytes > 0 ? bytes.formattedBytesCompact : "—")
                    .scaledFont(size: 17, weight: .bold)
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
                Text(localized("count.items", defaultValue: "\(items) items"))
                    .themeFont(.caption)
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
                Text(rank.formatted())
                    .themeFont(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textQuaternary)
                    .frame(width: 14, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(target.name)
                            .scaledFont(size: 13, weight: .medium)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Badge(for: target)
                    }
                    Text(target.category.title)
                        .themeFont(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 10)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(model.bytes(of: target).formattedBytesCompact)
                        .scaledFont(size: 12.5, weight: .medium)
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

/// A ranked project row in "Biggest single locations" — mirrors
/// BiggestRow, but routes to the Projects screen.
private struct ProjectFindingRow: View {
    let rank: Int
    let project: DiscoveredProject
    let fraction: Double
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Text(rank.formatted())
                    .themeFont(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textQuaternary)
                    .frame(width: 14, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Image(systemName: "folder.badge.gearshape")
                            .scaledFont(size: 11)
                            .foregroundStyle(Theme.textTertiary)
                        Text(project.name)
                            .scaledFont(size: 13, weight: .medium)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }
                    Text(localized("sidebar.projects", defaultValue: "Projects"))
                        .themeFont(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 10)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(project.artifactBytes.formattedBytesCompact)
                        .scaledFont(size: 12.5, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    MiniBar(fraction: fraction, color: Theme.accent)
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
                        .scaledFont(size: 13, weight: .medium)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(model.bytes(of: target).formattedBytesCompact)
                        .scaledFont(size: 12.5, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
                Text(target.summary)
                    .themeFont(.footnote)
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


/// Full Disk Access warning, restyled for the dark shell.
struct FullDiskAccessBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .scaledFont(size: 16)
                .foregroundStyle(Theme.cautionBright)
            VStack(alignment: .leading, spacing: 2) {
                Text(localized("fda.title", defaultValue: "Full Disk Access is not granted"))
                    .scaledFont(size: 13, weight: .medium)
                    .foregroundStyle(Theme.textPrimary)
                Text(localized(
                    "fda.body",
                    defaultValue: "Some locations cannot be measured or cleaned, so results may be incomplete."
                ))
                .themeFont(.caption)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button(localized("fda.openSettingsButton", defaultValue: "Open Privacy Settings…")) {
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
    OverviewView(
        openCategory: { _ in }, openTarget: { _ in },
        reviewEverything: {}, reclaimSafe: {}, openProjects: {}
    )
        .background(Theme.background)
        .environment(PreviewData.scanned())
        .preferredColorScheme(.dark)
}
#endif
