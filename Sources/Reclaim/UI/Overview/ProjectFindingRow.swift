//
//  ProjectFindingRow.swift
//  Reclaim
//
//  A ranked project row in the overview's "Biggest single locations"
//  list — mirrors BiggestRow, but routes to the Projects screen.
//

import ReclaimKit
import SwiftUI

/// A ranked project row in "Biggest single locations" — mirrors
/// BiggestRow, but routes to the Projects screen.
struct ProjectFindingRow: View {
    let rank: Int
    let project: DiscoveredProject
    let fraction: Double
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: Theme.rowGap) {
                Text(rank.formatted())
                    .themeFont(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textQuaternary)
                    .frame(width: 14, alignment: .leading)
                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    HStack(spacing: Theme.Space.s7) {
                        Image(systemName: "folder.badge.gearshape")
                            .themeFont(.caption)
                            .foregroundStyle(Theme.textTertiary)
                        Text(project.name)
                            .themeFont(.rowTitle)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }
                    Text(localized("sidebar.projects", defaultValue: "Projects"))
                        .themeFont(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 10)
                VStack(alignment: .trailing, spacing: Theme.Space.s5) {
                    Text(project.artifactBytes.formattedBytesCompact)
                        .themeFont(.amount)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    MiniBar(fraction: fraction, color: Theme.accent)
                }
                .frame(width: 110)
            }
            .padding(.vertical, Theme.Space.s10)
            .padding(.horizontal, Theme.Space.s8)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
        }
        .buttonStyle(.plain)
        .hoverHighlight(color: Theme.hoverFillQuiet)
    }
}
