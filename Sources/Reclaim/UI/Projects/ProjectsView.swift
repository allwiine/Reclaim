//
//  ProjectsView.swift
//  Reclaim
//
//  The dev-folder feature's screen, in the browser's two-column shape:
//  projects found in the user's development folders on the left, the
//  project inspector with per-artifact cherry-picking on the right.
//  Projects themselves are never cleanable — only their regenerable
//  artifacts. Inert (empty state) until a folder is added.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct ProjectsView: View {
    enum SortOrder: Hashable {
        case bySize, byActivity
    }

    @Environment(AppModel.self) var model
    /// Opens the per-project clean confirmation ("Clean just this").
    var onCleanProject: (DiscoveredProject) -> Void = { _ in }

    @State var sortOrder: SortOrder = .bySize
    @State var inspectedProjectID: DiscoveredProject.ID?

    var body: some View {
        Group {
            if model.projects.devRoots.isEmpty {
                emptyState
            } else {
                browser
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.gearshape")
                .scaledFont(size: 34, weight: .light)
                .foregroundStyle(Theme.textTertiary)
            Text(localized("projects.empty.title", defaultValue: "Find forgotten projects"))
                .scaledFont(size: 16, weight: .semibold)
                .foregroundStyle(Theme.textPrimary)
            Text(localized(
                "projects.empty.body",
                defaultValue: "Add the folders where your projects live. Reclaim finds git repositories and regenerable artifacts like node_modules and build folders, and shows what each project last did."
            ))
            .themeFont(.body)
            .lineSpacing(3.5)
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: 420)
            Button(localized("projects.addFolder", defaultValue: "Add a development folder…")) {
                for url in DevFolderPicker.pickFolders() {
                    model.projects.addDevRoot(url)
                }
            }
            .rcPrimary()
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Browser

    private var browser: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                strip

                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)

                listColumn
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Theme.divider)
                .frame(width: 1)

            ProjectInspectorPanel(
                project: inspectedProject,
                onCleanProject: onCleanProject
            )
            .frame(width: 336)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Empty", traits: .fixedLayout(width: 900, height: 620)) {
    ProjectsView()
        .background(Theme.background)
        .appEnvironment(PreviewData.idle())
        .preferredColorScheme(.dark)
}

#Preview("Browser", traits: .fixedLayout(width: 1060, height: 810)) {
    ProjectsView()
        .background(Theme.background)
        .appEnvironment(PreviewData.scannedWithProjects())
        .preferredColorScheme(.dark)
}
#endif
