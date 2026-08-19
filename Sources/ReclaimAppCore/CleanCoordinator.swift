//
//  CleanCoordinator.swift
//  ReclaimAppCore
//
//  The clean pass and its scan-time safety pins, split out of AppModel
//  so the god class sheds its cleaning plumbing while behavior stays
//  identical. The pass body lives in CleanCoordinator+Pass.swift and the
//  pins in CleanCoordinator+Safety.swift, both of which read the state
//  declared here — an extension in another file cannot reach `private`
//  members, so everything they touch stays internal.
//
//  Concurrency model
//  ─────────────────
//  The coordinator is @MainActor: every property the UI reads is
//  main-actor state. Blocking filesystem work (disposal, re-scanning,
//  probing) runs through `offMain`, which executes on the global
//  concurrent executor, off the main thread. The pass itself is
//  sequential on purpose: cleanup should be predictable and easy to
//  interrupt, and cancellation is only checked between jobs.
//

import Foundation
import Observation
import ReclaimKit

/// What a clean pass covers.
public enum CleanScope: Sendable, Equatable {
    /// Everything selected — registry targets and dev-folder artifacts.
    case selection
    /// Only the selected registry targets in the set ("Clean just
    /// this" on a target; artifacts never join).
    case targets(Set<CleanupTarget.ID>)
    /// Only the ticked artifacts of one project ("Clean just this"
    /// on a project; registry targets never join).
    case projectArtifacts(DiscoveredProject.ID)
}

@MainActor
@Observable
public final class CleanCoordinator {
    // MARK: - Session state

    /// The pass in flight, or `nil` when nothing is running. The pass
    /// body clears it as it unwinds, so it stays internal rather than
    /// `private(set)` — extensions in other files cannot write a
    /// file-private setter.
    @ObservationIgnored
    var cleanTask: Task<Void, Never>?

    // MARK: - Collaborators

    @ObservationIgnored
    let results: TargetResultsModel
    @ObservationIgnored
    let selection: SelectionModel
    @ObservationIgnored
    let projects: ProjectsModel
    @ObservationIgnored
    let breakdowns: BreakdownModel
    @ObservationIgnored
    let settings: SettingsStore
    @ObservationIgnored
    let activity: ActivityModel
    @ObservationIgnored
    let history: HistoryModel

    @ObservationIgnored
    let scanExecutor: ScanExecutor
    @ObservationIgnored
    let cleanExecutor: CleanExecutor
    @ObservationIgnored
    let projectScanExecutor: ProjectScanExecutor
    @ObservationIgnored
    let artifactCleanExecutor: ArtifactCleanExecutor
    @ObservationIgnored
    let volumeProbe: @Sendable () -> VolumeSpace?

    // MARK: - Init

    public init(
        executors: Executors,
        results: TargetResultsModel,
        selection: SelectionModel,
        projects: ProjectsModel,
        breakdowns: BreakdownModel,
        settings: SettingsStore,
        activity: ActivityModel,
        history: HistoryModel
    ) {
        self.results = results
        self.selection = selection
        self.projects = projects
        self.breakdowns = breakdowns
        self.settings = settings
        self.activity = activity
        self.history = history
        self.scanExecutor = executors.scan
        self.cleanExecutor = executors.clean
        self.projectScanExecutor = executors.projectScan
        self.artifactCleanExecutor = executors.artifactClean
        self.volumeProbe = executors.volume
    }

    // MARK: - Jobs

    struct CleanJob {
        let target: CleanupTarget
        let paths: [URL]
        let bytesBefore: Int64
        /// What the (possibly partial) selection is expected to free —
        /// dry-run projection only; real passes measure.
        let estimatedBytes: Int64
    }

    struct ArtifactCleanJob {
        let artifact: DiscoveredArtifact
        let projectName: String
        let devRoot: URL
    }

    // MARK: - Cleaning

    /// Clean what the scope covers — everything selected, one target's
    /// selection, or one project's ticked artifacts (the rest of the
    /// selection stays intact) — then re-scan the cleaned entries so
    /// the numbers on screen stay truthful.
    public func cleanSelected(scope: CleanScope = .selection) {
        guard !activity.isCleaning, !activity.isScanning else { return }
        guard !selection.ids.isEmpty || !projects.artifactSelection.isEmpty else { return }

        let targetLimit: Set<CleanupTarget.ID>? = switch scope {
        case .selection: nil
        case .targets(let ids): ids
        case .projectArtifacts: []      // registry targets never join
        }
        let jobs: [CleanJob] = results.targets.compactMap { target in
            guard selection.ids.contains(target.id), target.strategy.isCleanable,
                  targetLimit?.contains(target.id) != false else { return nil }
            switch results.status(of: target.id) {
            case .measured(let measurement, _, _):
                return CleanJob(
                    target: target,
                    paths: selection.selectedCleanupPaths(of: target),
                    bytesBefore: measurement.bytes,
                    estimatedBytes: selection.selectedBytes(of: target)
                )
            case .unmeasurable:
                return CleanJob(target: target, paths: [], bytesBefore: 0, estimatedBytes: 0)
            default:
                return nil
            }
        }
        // Artifact jobs join full passes and per-project passes —
        // "Clean just this" on a registry target stays a target affair.
        let artifactJobs: [ArtifactCleanJob]
        switch scope {
        case .targets:
            artifactJobs = []
        case .selection, .projectArtifacts:
            let projectLimit: DiscoveredProject.ID? =
                if case .projectArtifacts(let id) = scope { id } else { nil }
            artifactJobs = projects.projectScans.flatMap { scan in
                scan.projects
                    .filter { projectLimit == nil || $0.id == projectLimit }
                    .flatMap { project in
                        project.artifacts
                            .filter { projects.artifactSelection.contains($0.id) }
                            .map { ArtifactCleanJob(
                                artifact: $0, projectName: project.name, devRoot: scan.root
                            ) }
                    }
            }
        }
        guard !jobs.isEmpty || !artifactJobs.isEmpty else { return }

        // A dry run is a report, not a pass: project the numbers from
        // the scan-time snapshot and touch nothing — no engine, no
        // rescan, and the selection stays intact.
        if settings.dryRun {
            var summary = CleanSummary(disposal: settings.disposal)
            summary.isDryRun = true
            for job in jobs {
                summary.itemsRemoved += max(1, job.paths.count)
                summary.cleanedTargets += 1
                summary.reclaimedBytes += job.estimatedBytes
                summary.cleaned.append(CleanSummary.CleanedTarget(
                    id: job.target.id,
                    name: job.target.name,
                    category: job.target.category,
                    // Command targets have no measurable projection.
                    bytesFreed: job.paths.isEmpty ? nil : job.estimatedBytes
                ))
            }
            for job in artifactJobs {
                summary.itemsRemoved += 1
                summary.cleanedTargets += 1
                summary.reclaimedBytes += job.artifact.measurement.bytes
                summary.cleanedArtifacts.append(CleanSummary.CleanedArtifact(
                    id: job.artifact.id,
                    name: projects.artifactDisplayName(
                        kindID: job.artifact.kindID, projectName: job.projectName
                    ),
                    bytesFreed: job.artifact.measurement.bytes
                ))
            }
            activity.lastCleanSummary = summary
            return
        }

        startPass(jobs: jobs, artifactJobs: artifactJobs)
    }

    /// Stop the running clean pass after the in-flight target finishes.
    public func cancelClean() {
        guard cleanTask != nil else { return }
        activity.isCancellingClean = true
        cleanTask?.cancel()
    }

    /// Stop the running pass and wait for it to unwind, so the summary
    /// is published and the history recorded before the caller moves on.
    /// The in-flight target always finishes (cancellation is checked
    /// between jobs), so nothing is left half-cleaned.
    func cancelAndWait() async {
        activity.isCancellingClean = true
        cleanTask?.cancel()
        _ = await cleanTask?.value
    }
}
