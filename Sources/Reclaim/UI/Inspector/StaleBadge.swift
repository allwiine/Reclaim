//
//  StaleBadge.swift
//  Reclaim
//
//  "No recent activity" capsule shared by the project row and the
//  project inspector panel.
//

import SwiftUI

struct StaleBadge: View {
    var body: some View {
        Text(localized("projects.staleBadge", defaultValue: "No recent activity"))
            .themeFont(.caption)
            .foregroundStyle(Theme.cautionTitle)
            .padding(.horizontal, Theme.Space.s6)
            .padding(.vertical, Theme.Space.s2)
            .background(Theme.cautionTitle.opacity(0.12), in: Capsule())
    }
}
