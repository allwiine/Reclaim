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
        let bytes = results.categoryTotals().first { $0.category == category }?.bytes ?? 0
        let isSelected = destination == .category(category)

        return Button {
            destination = .category(category)
        } label: {
            HStack(spacing: Theme.Space.s10) {
                CategoryTile(category: category)
                Text(category.title)
                    .themeFont(.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(hasMeasurements && bytes > 0 ? bytes.formattedBytesCompact : "—")
                    .themeFont(.meta)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .contentTransition(.numericText())
                    .animation(Theme.smooth, value: bytes)
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

    var projectsRow: some View {
        let bytes = projects.projectArtifactBytes
        let isSelected = destination == .projects

        return Button {
            destination = .projects
        } label: {
            HStack(spacing: Theme.Space.s10) {
                Image(systemName: "folder.badge.gearshape")
                    .themeFont(.navIcon)
                    .foregroundStyle(Theme.textSubtle)
                    .frame(width: 22, height: 22)
                    .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: Theme.radiusIconChip))
                Text(localized("sidebar.projects", defaultValue: "Projects"))
                    .themeFont(.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(hasMeasurements && bytes > 0 ? bytes.formattedBytesCompact : "—")
                    .themeFont(.meta)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .contentTransition(.numericText())
                    .animation(Theme.smooth, value: bytes)
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
