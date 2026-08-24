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
                    Text(results.bytes(of: target).formattedBytesCompact)
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
