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
        HStack(spacing: Theme.Space.s8) {
            CategoryTile(category: category, size: 22)
            Text(category.title)
                .themeFont(.chipLabel)
                .foregroundStyle(Theme.textChipLabel)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.chipPaddingHorizontal)
        .padding(.vertical, Theme.chipPaddingVertical)
        .background(Theme.chipFill, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusControl)
                .strokeBorder(Theme.chipStroke, lineWidth: 0.5)
        }
    }

    var moreChip: some View {
        HStack(spacing: Theme.Space.s8) {
            Text(localized("idle.moreCategories", defaultValue: "\(hiddenChipCount) more"))
                .themeFont(.chipLabel)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.chipPaddingHorizontal)
        .padding(.vertical, Theme.chipPaddingVertical)
        .background(Theme.moreChipFill, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusControl)
                .strokeBorder(Theme.moreChipStroke, lineWidth: 0.5)
        }
    }
}
