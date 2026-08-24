//
//  ProjectInspectorPanel.swift
//  Reclaim
//
//  The projects screen's detail column: what a project is, when it
//  was last touched, and its regenerable artifacts with per-artifact
//  cherry-picking and a per-project clean action.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct ProjectInspectorPanel: View {
    @Environment(ProjectsModel.self) var projects
    @Environment(ActivityModel.self) var activity
    let project: DiscoveredProject?
    /// Opens the per-project clean confirmation ("Clean just this").
    var onCleanProject: (DiscoveredProject) -> Void = { _ in }

    var body: some View {
        Group {
            if let project {
                details(for: project)
            } else {
                Text(localized("projects.selectProject", defaultValue: "Select a project"))
                    .themeFont(.body)
                    .foregroundStyle(Theme.textQuaternary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.chromeFill)
    }

    private func details(for project: DiscoveredProject) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s0) {
                projectTile

                Text(project.name)
                    .themeFont(.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, Theme.Space.s14)

                HStack(spacing: Theme.Space.s8) {
                    if projects.isProjectStale(project) {
                        StaleBadge()
                    }
                    Text((project.devRoot.path as NSString).abbreviatingWithTildeInPath)
                        .themeFont(.meta)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                .padding(.top, Theme.Space.s8)

                sizeHeadline(for: project)
                    .padding(.top, Theme.Space.s16)

                activityLines(for: project)
                    .padding(.top, Theme.Space.s14)

                pathChip(for: project)
                    .padding(.top, Theme.Space.s14)

                artifactSection(for: project)
            }
            .padding(.horizontal, Theme.Space.s20)
            .padding(.top, Theme.Space.s18)
            .padding(.bottom, Theme.Space.s24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(project.id)
    }

}

// MARK: - Previews

#if DEBUG
#Preview("Project", traits: .fixedLayout(width: 336, height: 810)) {
    let model = PreviewData.scannedWithProjects()
    return ProjectInspectorPanel(project: model.projects.discovered.first)
        .background(Theme.background)
        .appEnvironment(model)
        .preferredColorScheme(.dark)
}

#Preview("No artifacts", traits: .fixedLayout(width: 336, height: 810)) {
    let model = PreviewData.scannedWithProjects()
    return ProjectInspectorPanel(project: model.projects.discovered.last)
        .background(Theme.background)
        .appEnvironment(model)
        .preferredColorScheme(.dark)
}
#endif
