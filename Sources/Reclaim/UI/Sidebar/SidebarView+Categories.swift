//
//  SidebarView+Categories.swift
//  Reclaim
//
//  The category navigation rows and the dev-folder Projects row
//  pinned beneath them.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension SidebarView {
    // MARK: - Category rows

    func categoryRow(_ category: ToolCategory) -> some View {
        let bytes = model.results.categoryTotals().first { $0.category == category }?.bytes ?? 0
        let isSelected = destination == .category(category)

        return Button {
            destination = .category(category)
        } label: {
            HStack(spacing: 10) {
                CategoryTile(category: category)
                Text(category.title)
                    .themeFont(.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(hasMeasurements && bytes > 0 ? bytes.formattedBytesCompact : "—")
                    .scaledFont(size: 12)
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: 0x8E8E95))
                    .contentTransition(.numericText())
                    .animation(Theme.smooth, value: bytes)
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

    var projectsRow: some View {
        let bytes = model.projects.projectArtifactBytes
        let isSelected = destination == .projects

        return Button {
            destination = .projects
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder.badge.gearshape")
                    .scaledFont(size: 10.5, weight: .medium)
                    .foregroundStyle(Color(hex: 0xB8B8BF))
                    .frame(width: 22, height: 22)
                    .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 6))
                Text(localized("sidebar.projects", defaultValue: "Projects"))
                    .themeFont(.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(hasMeasurements && bytes > 0 ? bytes.formattedBytesCompact : "—")
                    .scaledFont(size: 12)
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: 0x8E8E95))
                    .contentTransition(.numericText())
                    .animation(Theme.smooth, value: bytes)
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
