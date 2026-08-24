//
//  BrowserView.swift
//  Reclaim
//
//  The results browser: a selectable list of a category's targets (or
//  search matches) on the left, the detail inspector on the right.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct BrowserView: View {
    enum Mode: Equatable {
        case category(ToolCategory)
        /// Every visible target across categories ("Review everything").
        case all
        case search(String)
    }

    @Environment(TargetResultsModel.self) var results
    @Environment(ProjectsModel.self) var projects
    @Environment(SelectionModel.self) var selection
    let mode: Mode
    /// Row to anchor the inspector on when arriving from a tap on a
    /// specific target elsewhere (overview lists); `nil` falls back to
    /// the first row.
    var initialInspectedID: CleanupTarget.ID?
    /// Opens the single-target clean confirmation ("Clean just this").
    var onCleanSingle: (CleanupTarget) -> Void = { _ in }
    /// Routes to the Projects screen ("Review everything" covers
    /// dev-folder artifacts through a pointer row, not inline rows).
    var onOpenProjects: () -> Void = {}

    @State var inspectedID: CleanupTarget.ID?

    var body: some View {
        let targets = visibleTargets

        HStack(spacing: 0) {
            VStack(spacing: 0) {
                selectionStrip

                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)

                if targets.isEmpty && !showsProjectsRow {
                    emptyState
                } else {
                    list(targets)
                }
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Theme.divider)
                .frame(width: 1)

            InspectorPanel(target: inspectedTarget(in: targets), onCleanSingle: onCleanSingle)
                .frame(width: 336)
        }
        .onChange(of: mode, initial: true) { _, _ in
            // Entering a category (or refining a search) anchors the
            // inspector on the tapped target when one was passed in,
            // otherwise on the first row.
            inspectedID = initialInspectedID ?? visibleTargets.first?.id
        }
    }

    func inspectedTarget(in targets: [CleanupTarget]) -> CleanupTarget? {
        targets.first { $0.id == inspectedID } ?? targets.first
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Category", traits: .fixedLayout(width: 1060, height: 810)) {
    BrowserView(mode: .category(.xcode))
        .background(Theme.background)
        .appEnvironment(PreviewData.scanned())
        .preferredColorScheme(.dark)
}

#Preview("Search", traits: .fixedLayout(width: 1060, height: 810)) {
    BrowserView(mode: .search("cache"))
        .background(Theme.background)
        .appEnvironment(PreviewData.scanned())
        .preferredColorScheme(.dark)
}
#endif
