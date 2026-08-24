//
//  SidebarView+Headline.swift
//  Reclaim
//
//  The "Reclaimable" headline: the live total once anything has been
//  measured, a striped placeholder and a hint before that, and the
//  per-category share bar beneath the number.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension SidebarView {
    // MARK: - Headline

    var hasMeasurements: Bool {
        results.lastScan != nil || activity.isScanning
    }

    var headline: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s0) {
            SectionLabel(localized("sidebar.reclaimable", defaultValue: "Reclaimable"))

            if hasMeasurements {
                // Only what Reclaim itself can clean — tool-managed
                // items (Docker, Go modules) are found, not reclaimable.
                let parts = model.cleanableBytes.byteParts
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s6) {
                    Text(parts.value)
                        .font(Theme.heroNumber(31))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(Theme.smooth, value: parts.value)
                    Text(parts.unit)
                        .themeFont(.sidebarUnit)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, Theme.Space.s5)

                SegmentedBar(segments: categorySegments, height: 5)
                    .padding(.top, Theme.Space.s12)
            } else {
                HStack(alignment: .center, spacing: Theme.Space.s6) {
                    StripedPlaceholder()
                        .frame(width: 62, height: 22)
                    Text(localized("format.unitGigabytes", defaultValue: "GB"))
                        .themeFont(.sidebarUnit)
                        .foregroundStyle(Theme.textPlaceholderUnit)
                }
                .padding(.top, Theme.Space.s6)

                Text(localized("sidebar.runScanHint", defaultValue: "Run a scan to measure"))
                    .themeFont(.footnote)
                    .foregroundStyle(Theme.textQuaternary)
                    .padding(.top, Theme.Space.s9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Theme.smooth, value: hasMeasurements)
    }

    // The headline (`cleanableBytes`) counts dev-folder artifacts, so
    // the bar carries their share too — otherwise the composition
    // would silently attribute the projects' bytes to the categories.
    private var categorySegments: [MeterSegment] {
        let totals = results.categoryTotals(cleanableOnly: true)
        let projectBytes = projects.projectArtifactBytes
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
}
