//
//  CategoryView.swift
//  Reclaim
//
//  A category's targets as a selectable list.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct CategoryView: View {
    @Environment(AppModel.self) private var model
    let category: ToolCategory

    var body: some View {
        let visible = model.visibleTargets(in: category)

        Group {
            if visible.isEmpty {
                ContentUnavailableView {
                    Label("Nothing found", systemImage: category.systemImage)
                } description: {
                    Text("None of these tools were found on this Mac. Enable “Show tools that are not installed” in Settings to list them anyway.")
                }
            } else {
                List(visible) { target in
                    TargetRow(target: target)
                }
                .listStyle(.inset)
                .alternatingRowBackgrounds()
            }
        }
        .navigationSubtitle(category.title)
    }
}
