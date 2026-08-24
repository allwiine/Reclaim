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
    @Environment(AppModel.self) var model
    @Binding var destination: Destination

    var body: some View {
        VStack(spacing: 0) {
            // Breathing room for the window's traffic lights.
            Color.clear.frame(height: Theme.toolbarHeight)

            headline
                .padding(.horizontal, 18)
                .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 1) {
                    SidebarRow(
                        title: localized("sidebar.overview", defaultValue: "Overview"),
                        systemImage: "square.grid.2x2",
                        isSelected: destination == .overview
                    ) {
                        destination = .overview
                    }

                    SectionLabel(localized("sidebar.categories", defaultValue: "Categories"))
                        .padding(.horizontal, 10)
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(ToolCategory.allCases) { category in
                        categoryRow(category)
                    }

                    SectionLabel(localized("sidebar.development", defaultValue: "Development"))
                        .padding(.horizontal, 10)
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    projectsRow
                }
                .padding(.horizontal, 8)
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            VStack(spacing: 1) {
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
            .padding(8)
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
