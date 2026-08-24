//
//  BiggestRow.swift
//  Reclaim
//
//  A ranked row in the overview's "Biggest single locations" list.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

/// A ranked row in "Biggest single locations".
struct BiggestRow: View {
    @Environment(TargetResultsModel.self) private var results
    let rank: Int
    let target: CleanupTarget
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
                        Text(target.name)
                            .themeFont(.rowTitle)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Badge(for: target)
                    }
                    Text(target.category.title)
                        .themeFont(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 10)
                VStack(alignment: .trailing, spacing: Theme.Space.s5) {
                    Text(results.bytes(of: target).formattedBytesCompact)
                        .themeFont(.amount)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    MiniBar(fraction: fraction, color: BadgeKind(for: target).color)
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
