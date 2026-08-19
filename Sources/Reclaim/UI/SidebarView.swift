//
//  SidebarView.swift
//  Reclaim
//
//  The custom sidebar: the live "Reclaimable" headline with its
//  per-category share bar, category navigation, and the pinned
//  History/Settings footer.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Binding var destination: Destination

    var body: some View {
        VStack(spacing: 0) {
            // Breathing room for the window's traffic lights.
            Color.clear.frame(height: Theme.toolbarHeight)

            headline
                .padding(.horizontal, 18)
                .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 1) {
                    SidebarRow(
                        title: localized("sidebar.overview", defaultValue: "Overview"),
                        systemImage: "square.grid.2x2",
                        isSelected: destination == .overview
                    ) {
                        destination = .overview
                    }

                    SectionLabel(localized("sidebar.categories", defaultValue: "Categories"))
                        .padding(.horizontal, 10)
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(ToolCategory.allCases) { category in
                        categoryRow(category)
                    }

                    SectionLabel(localized("sidebar.development", defaultValue: "Development"))
                        .padding(.horizontal, 10)
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    projectsRow
                }
                .padding(.horizontal, 8)
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            VStack(spacing: 1) {
                SidebarRow(
                    title: localized("sidebar.history", defaultValue: "History"),
                    systemImage: "clock.arrow.circlepath",
                    isSelected: destination == .history
                ) {
                    destination = .history
                }
                SidebarRow(
                    title: localized("sidebar.settings", defaultValue: "Settings"),
                    systemImage: "gearshape",
                    isSelected: destination == .settings
                ) {
                    destination = .settings
                }
            }
            .padding(8)
        }
        .background(Theme.cardFillQuiet)
    }

    // MARK: - Headline

    private var hasMeasurements: Bool {
        model.results.lastScan != nil || model.activity.isScanning
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(localized("sidebar.reclaimable", defaultValue: "Reclaimable"))

            if hasMeasurements {
                // Only what Reclaim itself can clean — tool-managed
                // items (Docker, Go modules) are found, not reclaimable.
                let parts = model.cleanableBytes.byteParts
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(parts.value)
                        .font(Theme.heroNumber(31))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(Theme.smooth, value: parts.value)
                    Text(parts.unit)
                        .scaledFont(size: 15, weight: .medium)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, 5)

                SegmentedBar(segments: categorySegments, height: 5)
                    .padding(.top, 12)
            } else {
                HStack(alignment: .center, spacing: 6) {
                    StripedPlaceholder()
                        .frame(width: 62, height: 22)
                    Text(localized("format.unitGigabytes", defaultValue: "GB"))
                        .scaledFont(size: 15, weight: .medium)
                        .foregroundStyle(Color(hex: 0x5C5C63))
                }
                .padding(.top, 6)

                Text(localized("sidebar.runScanHint", defaultValue: "Run a scan to measure"))
                    .themeFont(.footnote)
                    .foregroundStyle(Theme.textQuaternary)
                    .padding(.top, 9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Theme.smooth, value: hasMeasurements)
    }

    // The headline (`cleanableBytes`) counts dev-folder artifacts, so
    // the bar carries their share too — otherwise the composition
    // would silently attribute the projects' bytes to the categories.
    private var categorySegments: [MeterSegment] {
        let totals = model.results.categoryTotals(cleanableOnly: true)
        let projectBytes = model.projects.projectArtifactBytes
        let sum = max(1, totals.reduce(Int64(0)) { $0 + $1.bytes } + projectBytes)
        var segments = totals.map { total in
            MeterSegment(
                id: total.category.id,
                fraction: Double(total.bytes) / Double(sum),
                color: total.category.color
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

    // MARK: - Category rows

    private func categoryRow(_ category: ToolCategory) -> some View {
        let bytes = model.results.categoryTotals().first { $0.category == category }?.bytes ?? 0
        let isSelected = destination == .category(category)

        return Button {
            destination = .category(category)
        } label: {
            HStack(spacing: 10) {
                CategoryTile(category: category)
                Text(category.title)
                    .themeFont(.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(hasMeasurements && bytes > 0 ? bytes.formattedBytesCompact : "—")
                    .scaledFont(size: 12)
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: 0x8E8E95))
                    .contentTransition(.numericText())
                    .animation(Theme.smooth, value: bytes)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Theme.selectionFill : .clear,
                in: RoundedRectangle(cornerRadius: Theme.radiusControl)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .animation(Theme.quick, value: isSelected)
    }

    private var projectsRow: some View {
        let bytes = model.projects.projectArtifactBytes
        let isSelected = destination == .projects

        return Button {
            destination = .projects
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder.badge.gearshape")
                    .scaledFont(size: 10.5, weight: .medium)
                    .foregroundStyle(Color(hex: 0xB8B8BF))
                    .frame(width: 22, height: 22)
                    .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 6))
                Text(localized("sidebar.projects", defaultValue: "Projects"))
                    .themeFont(.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(hasMeasurements && bytes > 0 ? bytes.formattedBytesCompact : "—")
                    .scaledFont(size: 12)
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: 0x8E8E95))
                    .contentTransition(.numericText())
                    .animation(Theme.smooth, value: bytes)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Theme.selectionFill : .clear,
                in: RoundedRectangle(cornerRadius: Theme.radiusControl)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .animation(Theme.quick, value: isSelected)
    }
}

// MARK: - Row

/// One navigation row with an icon chip, matching the design's list.
private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .scaledFont(size: 10.5, weight: .medium)
                    .foregroundStyle(Color(hex: 0xB8B8BF))
                    .frame(width: 22, height: 22)
                    .background(
                        Theme.controlFill,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                Text(title)
                    .themeFont(.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Theme.selectionFill : .clear,
                in: RoundedRectangle(cornerRadius: Theme.radiusControl)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .animation(Theme.quick, value: isSelected)
    }
}

/// Diagonal-stripe placeholder for not-yet-measured numbers.
struct StripedPlaceholder: View {
    var body: some View {
        stripes
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(localized("accessibility.notMeasuredYet", defaultValue: "Not measured yet"))
    }

    private var stripes: some View {
        GeometryReader { proxy in
            let step: CGFloat = 8
            Path { path in
                var x: CGFloat = -proxy.size.height
                while x < proxy.size.width + proxy.size.height {
                    path.move(to: CGPoint(x: x, y: proxy.size.height))
                    path.addLine(to: CGPoint(x: x + proxy.size.height, y: 0))
                    x += step
                }
            }
            .stroke(Color.white.opacity(0.075), lineWidth: 4)
            .background(Color.white.opacity(0.025))
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Measured", traits: .fixedLayout(width: 258, height: 700)) {
    @Previewable @State var destination = Destination.overview
    SidebarView(destination: $destination)
        .environment(PreviewData.scanned())
        .preferredColorScheme(.dark)
}

#Preview("Unmeasured", traits: .fixedLayout(width: 258, height: 700)) {
    @Previewable @State var destination = Destination.overview
    SidebarView(destination: $destination)
        .environment(PreviewData.idle())
        .preferredColorScheme(.dark)
}
#endif
