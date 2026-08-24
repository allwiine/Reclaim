//
//  SidebarRow.swift
//  Reclaim
//
//  One navigation row with an icon chip, matching the design's list.
//

import SwiftUI

/// One navigation row with an icon chip, matching the design's list.
struct SidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s10) {
                Image(systemName: systemImage)
                    .themeFont(.navIcon)
                    .foregroundStyle(Theme.textSubtle)
                    .frame(width: 22, height: 22)
                    .background(
                        Theme.controlFill,
                        in: RoundedRectangle(cornerRadius: Theme.radiusIconChip)
                    )
                Text(title)
                    .themeFont(.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.s10)
            .padding(.vertical, Theme.Space.s7)
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
