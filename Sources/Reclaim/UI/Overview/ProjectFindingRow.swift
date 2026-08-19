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
