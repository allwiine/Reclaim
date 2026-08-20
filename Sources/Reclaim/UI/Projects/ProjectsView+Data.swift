//
//  ProjectsView+Data.swift
//  Reclaim
//
//  The sorted project list, the roots that failed to scan, and which
//  project the detail column shows.
//

import Foundation
import ReclaimAppCore
import ReclaimKit

extension ProjectsView {
    // MARK: - Data

    var sortedProjects: [DiscoveredProject] {
        switch sortOrder {
        case .bySize:
            model.projects.discovered.sorted { $0.artifactBytes > $1.artifactBytes }
        case .byActivity:
            model.projects.discovered.sorted {
                ($0.lastActivityDate ?? .distantPast) < ($1.lastActivityDate ?? .distantPast)
            }
        }
    }

    var failedRoots: [DevRootScan] {
        model.projects.projectScans.filter { $0.failureMessage != nil }
    }

    /// The row the detail column shows: the clicked one, else the first.
    var inspectedProject: DiscoveredProject? {
        sortedProjects.first { $0.id == inspectedProjectID } ?? sortedProjects.first
    }
}
