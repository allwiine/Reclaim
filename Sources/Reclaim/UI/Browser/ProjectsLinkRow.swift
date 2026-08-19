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
            HStack(spacing: 12) {
                Image(systemName: "folder.badge.gearshape")
                    .scaledFont(size: 10.5, weight: .medium)
                    .foregroundStyle(Color(hex: 0xB8B8BF))
                    .frame(width: 22, height: 22)
                    .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("sidebar.projects", defaultValue: "Projects"))
                        .scaledFont(size: 13.5, weight: .medium)
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
                .scaledFont(size: 13, weight: .medium)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)

                Image(systemName: "chevron.right")
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(Theme.textQuaternary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusInset))
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: Theme.radiusInset, color: Color.white.opacity(0.055))
    }
}
