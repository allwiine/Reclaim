//
//  SidebarView.swift
//  Reclaim
//
//  Category navigation. Badges show measured totals per category once
//  a scan has run.
//

import ReclaimKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Label("Overview", systemImage: "internaldrive")
                .tag(SidebarItem.overview)

            Section("Categories") {
                ForEach(ToolCategory.allCases) { category in
                    Label(category.title, systemImage: category.systemImage)
                        .badge(Text(model.formattedCategoryTotal(category) ?? ""))
                        .tag(SidebarItem.category(category))
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 240)
    }
}
