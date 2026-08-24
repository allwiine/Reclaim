//
//  BrowserView+List.swift
//  Reclaim
//
//  The scrollable target list (plus the trailing Projects pointer row),
//  and the empty state shown when nothing matches the current mode.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension BrowserView {
    // MARK: - List

    func list(_ targets: [CleanupTarget]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.Space.s0) {
                    ForEach(targets) { target in
                        TargetRow(
                            target: target,
                            isInspected: inspectedTarget(in: targets)?.id == target.id,
                            maxBytes: targets.map { results.bytes(of: $0) }.max() ?? 0
                        ) {
                            inspectedID = target.id
                        }
                    }
                    if showsProjectsRow {
                        ProjectsLinkRow(
                            count: projects.projectsWithArtifactsCount,
                            bytes: projects.projectArtifactBytes,
                            open: onOpenProjects
                        )
                    }
                }
                .padding(.horizontal, Theme.Space.s8)
                .padding(.top, Theme.Space.s6)
                .padding(.bottom, Theme.Space.s20)
            }
            // A target tapped elsewhere may sit below the fold in long
            // categories — reveal it. (Rows clicked in this list are
            // already visible, so this is a no-op for them.)
            .onChange(of: inspectedID, initial: true) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    var emptyState: some View {
        VStack(spacing: Theme.Space.s10) {
            Image(systemName: emptyIcon)
                .themeFont(.emptyStateIcon)
                .foregroundStyle(Theme.textQuaternary)
            Text(emptyTitle)
                .themeFont(.emptyStateTitle)
                .foregroundStyle(Theme.textSecondary)
            Text(emptyDetail)
                .themeFont(.body)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyIcon: String {
        if case .search = mode { return "magnifyingglass" }
        return "tray"
    }

    private var emptyTitle: String {
        if case .search = mode {
            return localized("browser.noMatches", defaultValue: "No matches")
        }
        return localized("browser.nothingFound", defaultValue: "Nothing found")
    }

    private var emptyDetail: String {
        switch mode {
        case .search:
            localized(
                "browser.emptySearchDetail",
                defaultValue: "No catalogue entry matches that search — try a tool name or a path fragment."
            )
        case .category, .all:
            localized(
                "browser.emptyCategoryDetail",
                defaultValue: "Nothing here right now — these tools are either not installed or have nothing to clean. Settings can keep such entries visible."
            )
        }
    }
}
