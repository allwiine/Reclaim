//
//  AppModel+Overview.swift
//  ReclaimAppCore
//
//  The cross-model aggregates the overview screen reads: totals and
//  "biggest findings" that span registry targets and dev-folder projects
//  alike. They live on the composition root because no single sub-model
//  owns both halves.
//

import Foundation
import ReclaimKit

/// One entry in the overview's "biggest single locations" list —
/// either a registry target or a discovered project. Projects are
/// represented whole (their artifact total), not per artifact,
/// matching how the Projects screen presents them.
public enum OverviewFinding: Identifiable, Sendable {
    case target(CleanupTarget, bytes: Int64)
    case project(DiscoveredProject)

    public var id: String {
        switch self {
        case .target(let target, _): "target:\(target.id)"
        case .project(let project): "project:\(project.id)"
        }
    }

    public var bytes: Int64 {
        switch self {
        case .target(_, let bytes): bytes
        case .project(let project): project.artifactBytes
        }
    }
}

extension AppModel {
    // MARK: - Derived state

    /// Everything measured, including manual-only items like Docker and
    /// dev-folder artifacts.
    public var totalFoundBytes: Int64 {
        results.targets.reduce(0) { $0 + (results.status(of: $1.id).bytes ?? 0) }
            + projects.projectArtifactBytes
    }

    /// Only what Reclaim itself can clean, including dev-folder artifacts.
    public var cleanableBytes: Int64 {
        results.targets.reduce(0) { sum, target in
            guard target.strategy.isCleanable else { return sum }
            return sum + (results.status(of: target.id).bytes ?? 0)
        } + projects.projectArtifactBytes
    }

    /// Bytes covered by the current selection, partial picks and
    /// selected dev-folder artifacts included.
    public var selectedBytes: Int64 {
        results.targets.reduce(0) { $0 + selection.selectedBytes(of: $1) }
            + projects.selectedArtifactBytes
    }

    // MARK: - Dev-folder projects

    /// The largest measured findings across registry targets and
    /// dev-folder projects, by size.
    public func largestFindings(limit: Int) -> [OverviewFinding] {
        let targetFindings: [OverviewFinding] = results.targets.compactMap { target in
            let bytes = results.status(of: target.id).bytes ?? 0
            return bytes > 0 ? .target(target, bytes: bytes) : nil
        }
        let projectFindings: [OverviewFinding] = projects.discovered
            .filter { $0.artifactBytes > 0 }
            .map { .project($0) }
        return (targetFindings + projectFindings)
            .sorted { $0.bytes > $1.bytes }
            .prefix(limit)
            .map { $0 }
    }

    /// Whether a clean pass has anything to do — registry targets or
    /// dev-folder artifacts. Derived from live projects (via
    /// ``ProjectsModel/selectedArtifacts``), not the raw id set, so ids
    /// left dangling by a root removed out from under the selection
    /// never count.
    public var hasCleanableSelection: Bool {
        !selection.ids.isEmpty || !projects.selectedArtifacts.isEmpty
    }
}
