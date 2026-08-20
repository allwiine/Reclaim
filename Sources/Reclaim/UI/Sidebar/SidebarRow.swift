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
