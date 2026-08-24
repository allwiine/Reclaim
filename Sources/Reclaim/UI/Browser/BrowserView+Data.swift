//
//  BrowserView+Data.swift
//  Reclaim
//
//  The browser's target list for the current mode, and whether the
//  dev-folder pointer row belongs at the end of it.
//

import Foundation
import ReclaimAppCore
import ReclaimKit

extension BrowserView {
    // MARK: - Data

    var visibleTargets: [CleanupTarget] {
        switch mode {
        case .category(let category):
            return results.visibleTargets(in: category)
        case .all:
            return results.allVisibleTargets
        case .search(let query):
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return [] }
            return results.targets.filter { target in
                target.name.localizedCaseInsensitiveContains(trimmed)
                    || target.summary.localizedCaseInsensitiveContains(trimmed)
                    || target.category.title.localizedCaseInsensitiveContains(trimmed)
                    || target.pathPatterns.contains {
                        $0.localizedCaseInsensitiveContains(trimmed)
                    }
            }
        }
    }

    /// "Review everything" would under-account the headline it sits
    /// beneath without the projects' bytes — they get a pointer row.
    var showsProjectsRow: Bool {
        mode == .all && projects.projectArtifactBytes > 0
    }
}
