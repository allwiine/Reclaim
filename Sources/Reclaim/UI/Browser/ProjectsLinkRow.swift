//
//  ProjectsLinkRow.swift
//  Reclaim
//
//  The dev-folder pointer at the end of "Review everything": projects
//  are part of the totals above, but their artifacts are reviewed and
//  cleaned on the Projects screen, so this row routes there instead of
//  offering a checkbox.
//

import SwiftUI

struct ProjectsLinkRow: View {
    let count: Int
    let bytes: Int64
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: Theme.rowGap) {
                Image(systemName: "folder.badge.gearshape")
                    .themeFont(.navIcon)
                    .foregroundStyle(Theme.textSubtle)
                    .frame(width: 22, height: 22)
                    .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: Theme.radiusIconChip))

                VStack(alignment: .leading, spacing: Theme.Space.s3) {
                    Text(localized("sidebar.projects", defaultValue: "Projects"))
                        .themeFont(.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(localized(
                        "browser.projectsRowSubtitle",
                        defaultValue: "Reviewed and cleaned on the Projects screen"
                    ))
                    .themeFont(.caption)
                    .foregroundStyle(Theme.textTertiary)
                }

                Spacer(minLength: 10)

                Text(localized(
                    "toolbar.projectsSubtitle",
                    defaultValue: "\(count) projects · \(bytes.formattedBytesCompact)"
                ))
                .themeFont(.rowTitle)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)

                Image(systemName: "chevron.right")
                    .themeFont(.disclosure)
                    .foregroundStyle(Theme.textQuaternary)
            }
            .padding(.horizontal, Theme.Space.s12)
            .padding(.vertical, Theme.Space.s10)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusInset))
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: Theme.radiusInset, color: Theme.hoverFillRow)
    }
}
