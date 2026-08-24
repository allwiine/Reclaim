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
            VStack(alignment: .leading, spacing: Theme.Space.s10) {
                HStack {
                    SectionLabel(localized("sidebar.projects", defaultValue: "Projects"))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .themeFont(.disclosure)
                        .foregroundStyle(Theme.textQuaternary)
                }
                if projects.discovered.isEmpty {
                    Text(localized(
                        "projects.noneFound",
                        defaultValue: "No projects found in the added folders."
                    ))
                    .themeFont(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                } else {
                    Text(localized(
                        "toolbar.projectsSubtitle",
                        defaultValue: "\(projects.discovered.count) projects · \(projects.projectArtifactBytes.formattedBytesCompact)"
                    ))
                    .themeFont(.figure)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(Theme.smooth, value: projects.projectArtifactBytes)

                    VStack(spacing: Theme.Space.s6) {
                        ForEach(projects.largestProjects(limit: 2)) { project in
                            HStack(spacing: Theme.Space.s8) {
                                Image(systemName: "folder.badge.gearshape")
                                    .themeFont(.miniIcon)
                                    .foregroundStyle(Theme.textTertiary)
                                Text(project.name)
                                    .themeFont(.meta)
                                    .foregroundStyle(Theme.textRowLabel)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(project.artifactBytes.formattedBytesCompact)
                                    .themeFont(.meta)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.s16)
            .padding(.vertical, Theme.Space.s13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusTile))
        }
        .buttonStyle(.plain)
        .card(radius: Theme.radiusTile)
        .hoverHighlight()
    }

    // MARK: - Attention & stats

    var attentionCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            SectionLabel(localized("overview.needsAttention", defaultValue: "Needs your attention"))
            VStack(spacing: Theme.Space.s10) {
                ForEach(results.manualTargets) { target in
                    AttentionCard(target: target) {
                        openTarget(target)
                    }
                }
            }
        }
        .padding(Theme.Space.s18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

}
