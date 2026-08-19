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
    @Environment(AppModel.self) var model
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
        .background(Color.white.opacity(0.02))
    }

    private func details(for project: DiscoveredProject) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                projectTile

                Text(project.name)
                    .scaledFont(size: 17, weight: .bold)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 14)

                HStack(spacing: 8) {
                    if model.projects.isProjectStale(project) {
                        StaleBadge()
                    }
                    Text((project.devRoot.path as NSString).abbreviatingWithTildeInPath)
                        .scaledFont(size: 12)
                        .foregroundStyle(Color(hex: 0x8E8E95))
                        .lineLimit(1)
                }
                .padding(.top, 8)

                sizeHeadline(for: project)
                    .padding(.top, 16)

                activityLines(for: project)
                    .padding(.top, 14)

                pathChip(for: project)
                    .padding(.top, 14)

                artifactSection(for: project)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
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
        .environment(model)
        .preferredColorScheme(.dark)
}

#Preview("No artifacts", traits: .fixedLayout(width: 336, height: 810)) {
    let model = PreviewData.scannedWithProjects()
    return ProjectInspectorPanel(project: model.projects.discovered.last)
        .background(Theme.background)
        .environment(model)
        .preferredColorScheme(.dark)
}
#endif
