//
//  SidebarView.swift
//  Reclaim
//
//  The custom sidebar: the live "Reclaimable" headline with its
//  per-category share bar, category navigation, and the pinned
//  History/Settings footer.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct SidebarView: View {
    /// Kept for `cleanableBytes` only — a cross-model member.
    @Environment(AppModel.self) var model
    @Environment(TargetResultsModel.self) var results
    @Environment(ActivityModel.self) var activity
    @Environment(ProjectsModel.self) var projects
    @Binding var destination: Destination

    var body: some View {
        VStack(spacing: Theme.Space.s0) {
            // Breathing room for the window's traffic lights.
            Color.clear.frame(height: Theme.toolbarHeight)

            headline
                .padding(.horizontal, Theme.Space.s18)
                .padding(.bottom, Theme.Space.s16)

            ScrollView {
                VStack(spacing: Theme.Space.s1) {
                    SidebarRow(
                        title: localized("sidebar.overview", defaultValue: "Overview"),
                        systemImage: "square.grid.2x2",
                        isSelected: destination == .overview
                    ) {
                        destination = .overview
                    }

                    SectionLabel(localized("sidebar.categories", defaultValue: "Categories"))
                        .padding(.horizontal, Theme.Space.s10)
                        .padding(.top, Theme.Space.s14)
                        .padding(.bottom, Theme.Space.s8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(ToolCategory.allCases) { category in
                        categoryRow(category)
                    }

                    SectionLabel(localized("sidebar.development", defaultValue: "Development"))
                        .padding(.horizontal, Theme.Space.s10)
                        .padding(.top, Theme.Space.s14)
                        .padding(.bottom, Theme.Space.s8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    projectsRow
                }
                .padding(.horizontal, Theme.Space.s8)
            }

            Rectangle()
                .fill(Theme.dividerStrong)
                .frame(height: 1)

            VStack(spacing: Theme.Space.s1) {
                SidebarRow(
                    title: localized("sidebar.history", defaultValue: "History"),
                    systemImage: "clock.arrow.circlepath",
                    isSelected: destination == .history
                ) {
                    destination = .history
                }
                SidebarRow(
                    title: localized("sidebar.settings", defaultValue: "Settings"),
                    systemImage: "gearshape",
                    isSelected: destination == .settings
                ) {
                    destination = .settings
                }
            }
            .padding(Theme.Space.s8)
        }
        .background(Theme.cardFillQuiet)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Measured", traits: .fixedLayout(width: 258, height: 700)) {
    @Previewable @State var destination = Destination.overview
    SidebarView(destination: $destination)
        .appEnvironment(PreviewData.scanned())
        .preferredColorScheme(.dark)
}

#Preview("Unmeasured", traits: .fixedLayout(width: 258, height: 700)) {
    @Previewable @State var destination = Destination.overview
    SidebarView(destination: $destination)
        .appEnvironment(PreviewData.idle())
        .preferredColorScheme(.dark)
}
#endif
