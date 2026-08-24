//
//  ProjectsView+List.swift
//  Reclaim
//
//  The scrollable project list: failed-root notices first, then a
//  hint or the sorted projects.
//

import AppKit
import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension ProjectsView {
    // MARK: - List column

    var listColumn: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(failedRoots) { scan in
                    failedRootRow(scan)
                }

                if results.lastScan == nil {
                    hintText(localized(
                        "projects.notScanned",
                        defaultValue: "Run a scan to find projects and artifacts."
                    ))
                } else if projects.discovered.isEmpty {
                    hintText(localized(
                        "projects.noneFound",
                        defaultValue: "No projects found in the added folders."
                    ))
                } else {
                    ForEach(sortedProjects) { project in
                        ProjectRow(
                            project: project,
                            isInspected: inspectedProject?.id == project.id,
                            maxBytes: sortedProjects.map(\.artifactBytes).max() ?? 0
                        ) {
                            inspectedProjectID = project.id
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 20)
        }
    }

    private func hintText(_ text: String) -> some View {
        Text(text)
            .themeFont(.body)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func failedRootRow(_ scan: DevRootScan) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .scaledFont(size: 12)
                .foregroundStyle(Theme.cautionTitle)
            Text((scan.root.path as NSString).abbreviatingWithTildeInPath)
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.textSecondary)
            Text(scan.failureMessage ?? "")
                .themeFont(.caption)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .card(radius: Theme.radiusInset)
        .padding(.bottom, 6)
    }
}
