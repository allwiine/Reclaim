//
//  CategoryCard.swift
//  Reclaim
//
//  One tile in the overview's category grid.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

/// One tile in the category grid.
struct CategoryCard: View {
    /// Kept for `totalFoundBytes` only — a cross-model member.
    @Environment(AppModel.self) private var model
    @Environment(TargetResultsModel.self) private var results
    let category: ToolCategory
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        let totals = results.categoryTotals()
        let bytes = totals.first { $0.category == category }?.bytes ?? 0
        // Share of everything found, dev-folder artifacts included —
        // the same denominator as the overview ring.
        let all = model.totalFoundBytes
        let peak = totals.map(\.bytes).max() ?? 1
        let items = results.targets.count { $0.category == category && results.bytes(of: $0) > 0 }

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
