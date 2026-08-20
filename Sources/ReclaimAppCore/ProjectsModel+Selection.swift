//
//  ProjectsModel+Selection.swift
//  ReclaimAppCore
//
//  Ticking dev-folder artifacts and whole projects for cleaning, plus
//  the tri-state counts the project row's checkbox needs. Split out of
//  AppModel together with the rest of the projects state; the state it
//  reads and writes is declared on ``ProjectsModel`` itself.
//

import Foundation
import ReclaimKit

extension ProjectsModel {
    // MARK: - Artifact selection

    /// Whether the artifact's checkbox is enabled.
    public func isArtifactSelectable(_ artifact: DiscoveredArtifact) -> Bool {
        !activity.isScanning && !activity.isCleaning && artifact.measurement.bytes > 0
    }

    public func isArtifactSelected(_ artifact: DiscoveredArtifact) -> Bool {
        artifactSelection.contains(artifact.id)
    }

    public func setArtifactSelected(_ artifact: DiscoveredArtifact, _ selected: Bool) {
        if selected, isArtifactSelectable(artifact) {
            artifactSelection.insert(artifact.id)
        } else {
            artifactSelection.remove(artifact.id)
        }
    }

    /// The selected artifacts, discovery order.
    public var selectedArtifacts: [DiscoveredArtifact] {
        discovered.flatMap(\.artifacts).filter { artifactSelection.contains($0.id) }
    }

    public var selectedArtifactBytes: Int64 {
        selectedArtifacts.reduce(0) { $0 + $1.measurement.bytes }
    }

    // MARK: - Project selection

    /// Whether the project row's checkbox is enabled: it has at least
    /// one artifact with measurable bytes to free.
    public func isProjectSelectable(_ project: DiscoveredProject) -> Bool {
        !activity.isScanning && !activity.isCleaning
            && project.artifacts.contains { $0.measurement.bytes > 0 }
    }

    /// The project's ticked artifacts, discovery order.
    public func selectedArtifacts(of project: DiscoveredProject) -> [DiscoveredArtifact] {
        project.artifacts.filter { artifactSelection.contains($0.id) }
    }

    public func selectedArtifactBytes(of project: DiscoveredProject) -> Int64 {
        selectedArtifacts(of: project).reduce(0) { $0 + $1.measurement.bytes }
    }

    /// Selected vs selectable artifact counts backing the tri-state.
    private func artifactSelectionCounts(
        of project: DiscoveredProject
    ) -> (selected: Int, selectable: Int) {
        (
            selected: selectedArtifacts(of: project).count,
            selectable: project.artifacts.count { $0.measurement.bytes > 0 }
        )
    }

    /// Whether every selectable artifact of the project is ticked (the
    /// row checkbox's "on"; empty artifacts never count).
    public func isProjectSelected(_ project: DiscoveredProject) -> Bool {
        let counts = artifactSelectionCounts(of: project)
        return counts.selected > 0 && counts.selected == counts.selectable
    }

    /// Whether some but not all selectable artifacts are ticked (the
    /// row checkbox's mixed state).
    public func isProjectPartiallySelected(_ project: DiscoveredProject) -> Bool {
        let counts = artifactSelectionCounts(of: project)
        return counts.selected > 0 && counts.selected < counts.selectable
    }

    /// Tick or untick all of the project's artifacts (empty ones are
    /// refused by the per-artifact rule).
    public func setProjectSelected(_ project: DiscoveredProject, _ selected: Bool) {
        for artifact in project.artifacts {
            setArtifactSelected(artifact, selected)
        }
    }

    /// "K of M items" while the project is cherry-picked; nil when
    /// nothing or everything selectable is ticked (mirrors the target
    /// counterpart).
    public func partialSelectionCounts(
        of project: DiscoveredProject
    ) -> (selected: Int, total: Int)? {
        guard isProjectPartiallySelected(project) else { return nil }
        let counts = artifactSelectionCounts(of: project)
        return (selected: counts.selected, total: counts.selectable)
    }

    /// Artifacts with measurable bytes across all projects — the
    /// projects strip summary's denominator.
    public var selectableArtifactCount: Int {
        discovered.flatMap(\.artifacts).count { $0.measurement.bytes > 0 }
    }

    /// Tick every selectable artifact across all projects.
    public func selectAllArtifacts() {
        for project in discovered { setProjectSelected(project, true) }
    }

    /// Untick every artifact. The registry-target selection stays.
    public func clearArtifactSelection() {
        artifactSelection.removeAll()
    }
}
