//
//  OverviewView+Sidebar.swift
//  Reclaim
//
//  The overview's right-hand column: the compact Projects summary and
//  the "needs your attention" tool callouts.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension OverviewView {
    // MARK: - Projects card

    /// Compact dev-folder summary: how much the discovered projects'
    /// artifacts hold, and the biggest offenders. Tapping anywhere
    /// opens the Projects screen. Shown only once dev folders exist.
    var projectsCard: some View {
        Button(action: openProjects) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(localized("sidebar.projects", defaultValue: "Projects"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .scaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(Theme.textQuaternary)
                }
                if model.projects.discovered.isEmpty {
                    Text(localized(
                        "projects.noneFound",
                        defaultValue: "No projects found in the added folders."
                    ))
                    .themeFont(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                } else {
                    Text(localized(
                        "toolbar.projectsSubtitle",
                        defaultValue: "\(model.projects.discovered.count) projects · \(model.projects.projectArtifactBytes.formattedBytesCompact)"
                    ))
                    .scaledFont(size: 14, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(Theme.smooth, value: model.projects.projectArtifactBytes)

                    VStack(spacing: 6) {
                        ForEach(model.projects.largestProjects(limit: 2)) { project in
                            HStack(spacing: 8) {
                                Image(systemName: "folder.badge.gearshape")
                                    .scaledFont(size: 10.5)
                                    .foregroundStyle(Theme.textTertiary)
                                Text(project.name)
                                    .scaledFont(size: 12)
                                    .foregroundStyle(Color(hex: 0xB4B4BB))
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(project.artifactBytes.formattedBytesCompact)
                                    .scaledFont(size: 12)
                                    .monospacedDigit()
                                    .foregroundStyle(Color(hex: 0x8E8E95))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusTile))
        }
        .buttonStyle(.plain)
        .card(radius: Theme.radiusTile)
        .hoverHighlight()
    }

    // MARK: - Attention & stats

    var attentionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(localized("overview.needsAttention", defaultValue: "Needs your attention"))
            VStack(spacing: 10) {
                ForEach(model.results.manualTargets) { target in
                    AttentionCard(target: target) {
                        openTarget(target)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

}
