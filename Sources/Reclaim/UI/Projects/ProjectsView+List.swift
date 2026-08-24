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
            LazyVStack(spacing: Theme.Space.s0) {
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
            .padding(.horizontal, Theme.Space.s8)
            .padding(.top, Theme.Space.s6)
            .padding(.bottom, Theme.Space.s20)
        }
    }

    private func hintText(_ text: String) -> some View {
        Text(text)
            .themeFont(.body)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, Theme.Space.s8)
            .padding(.top, Theme.Space.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func failedRootRow(_ scan: DevRootScan) -> some View {
        HStack(spacing: Theme.Space.s10) {
            Image(systemName: "exclamationmark.triangle")
                .themeFont(.meta)
                .foregroundStyle(Theme.cautionTitle)
            Text((scan.root.path as NSString).abbreviatingWithTildeInPath)
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.textSecondary)
            Text(scan.failureMessage ?? "")
                .themeFont(.caption)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s10)
        .card(radius: Theme.radiusInset)
        .padding(.bottom, Theme.Space.s6)
    }
}
