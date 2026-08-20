//
//  IdleView+Chips.swift
//  Reclaim
//
//  The catalogue card's category-chip grid: the visible chips, the
//  folded "+N more" chip, and the ceiling that decides between them.
//

import ReclaimKit
import SwiftUI

extension IdleView {
    /// Ceiling on category chips before the card folds into "+N more".
    private static let maxVisibleChips = 14

    var visibleChipCategories: [ToolCategory] {
        let all = ToolCategory.allCases
        guard all.count > Self.maxVisibleChips else { return all }
        return Array(all.prefix(Self.maxVisibleChips - 1))
    }

    var hiddenChipCount: Int {
        ToolCategory.allCases.count - visibleChipCategories.count
    }

    func categoryChip(_ category: ToolCategory) -> some View {
        HStack(spacing: 8) {
            CategoryTile(category: category, size: 22)
            Text(category.title)
                .scaledFont(size: 11.5, weight: .medium)
                .foregroundStyle(Color(hex: 0xC8C8CF))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.05), lineWidth: 0.5)
        }
    }

    var moreChip: some View {
        HStack(spacing: 8) {
            Text(localized("idle.moreCategories", defaultValue: "\(hiddenChipCount) more"))
                .scaledFont(size: 11.5, weight: .medium)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.04), lineWidth: 0.5)
        }
    }
}
