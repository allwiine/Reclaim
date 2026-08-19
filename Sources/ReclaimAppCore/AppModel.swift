//
//  AppModel.swift
//  ReclaimAppCore
//
//  The single observable source of truth for the UI. Owns per-target
//  scan status, selection, settings, and orchestrates background work.
//  Lives in a UI-free library target so the whole orchestration layer
//  is unit-testable; the scan/clean executors are injectable seams.
//
//  Concurrency model
//  ─────────────────
//  The model is @MainActor: every property the UI reads is main-actor
//  state. Blocking filesystem work (sizing, deleting) runs through
//  `offMain`, a `nonisolated` async helper, which — with this package's
//  settings (no NonisolatedNonsendingByDefault / no default MainActor
//  isolation) — executes on the global concurrent executor, off the
//  main thread. Scans fan out through a task group with bounded width
//  so disk I/O never saturates the cooperative thread pool.
//

import Foundation
import Observation
import ReclaimKit

@MainActor
@Observable
public final class AppModel {
    // MARK: - Constants

    /// Maximum directory walks in flight at once. Disk-bound work gains
    /// little from more parallelism and would block cooperative threads.
    private static let maxConcurrentScans = 4

    // MARK: - Session state

    /// Per-target scan results and the totals derived from them.
    public let results: TargetResultsModel

    /// When the last *completed* (non-cancelled) scan finished. Anchors
    /// the weekly background schedule and, being observable, keeps the
    /// footer's "next background scan" line live.
    public private(set) var lastCompletedScanDate: Date?

    /// What the app is doing right now — pass flags, progress, and the
    /// latest pass outcome.
    public let activity = ActivityModel()

    /// Persistent clean history.
    public let history: HistoryModel

    /// On-demand "largest contents" cache per target.
    public let breakdowns: BreakdownModel

    /// What the user has ticked for cleaning, whole targets and
    /// cherry-picked paths alike.
    public let selection: SelectionModel

    /// Dev-folder roots, discovery results, and artifact selection.
    public let projects: ProjectsModel

    @ObservationIgnored
    private(set) var scanTask: Task<Void, Never>?
    @ObservationIgnored
    private(set) var cleanTask: Task<Void, Never>?

    @ObservationIgnored
    private let scanExecutor: ScanExecutor
    @ObservationIgnored
    private let cleanExecutor: CleanExecutor
    @ObservationIgnored
    private let projectScanExecutor: ProjectScanExecutor
    @ObservationIgnored
    private let artifactCleanExecutor: ArtifactCleanExecutor
    @ObservationIgnored
    private let fullDiskAccessProbe: @Sendable () -> Bool?
    @ObservationIgnored
    private let volumeProbe: @Sendable () -> VolumeSpace?

    // MARK: - Persisted settings

    private let defaults: UserDefaults

    /// UserDefaults-backed settings, split out of this model.
    public let settings: SettingsStore

    private enum DefaultsKey {
        static let lastScanDate = "state.lastScanDate"
    }

    /// How often the background scan runs while the app is open.
    public static let backgroundScanInterval: TimeInterval = 7 * 24 * 3600

    // MARK: - Init

    public init(
        targets: [CleanupTarget] = TargetRegistry.all,
        defaults: UserDefaults = .standard,
        executors: Executors = Executors(),
        historyStore: CleanHistoryStore = CleanHistoryStore()
    ) {
        self.defaults = defaults
        let settings = SettingsStore(defaults: defaults)
        self.settings = settings
        self.results = TargetResultsModel(
            targets: targets, settings: settings, volumeProbe: executors.volume
        )
        self.breakdowns = BreakdownModel(results: results, executor: executors.breakdown)
        self.selection = SelectionModel(
            results: results, activity: activity, breakdowns: breakdowns, defaults: defaults
        )
        self.projects = ProjectsModel(activity: activity, defaults: defaults)
        self.scanExecutor = executors.scan
        self.cleanExecutor = executors.clean
        self.projectScanExecutor = executors.projectScan
        self.artifactCleanExecutor = executors.artifactClean
        self.fullDiskAccessProbe = executors.fullDiskAccess
        self.volumeProbe = executors.volume
        self.history = HistoryModel(store: historyStore)
        self.lastCompletedScanDate = defaults.object(forKey: DefaultsKey.lastScanDate) as? Date
        results.refreshVolumeSpace()
    }

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

    // MARK: - Background scanning

    /// When the next automatic scan is due, or `nil` when disabled or
    /// no scan has happened yet.
    public var nextBackgroundScanDate: Date? {
        guard settings.weeklyScanEnabled else { return nil }
        guard let last = lastCompletedScanDate else { return nil }
        return last.addingTimeInterval(Self.backgroundScanInterval)
    }

    /// Start a scan if the weekly background scan is enabled and due.
    /// Called periodically by the app layer while Reclaim is running.
    /// Defers while the confirmation sheet is up — a background scan
    /// must never clear a selection the user is actively reviewing.
    public func runBackgroundScanIfDue(now: Date = .now) {
        guard settings.weeklyScanEnabled, !activity.isScanning, !activity.isCleaning, !activity.isReviewingSelection else { return }
        guard let next = nextBackgroundScanDate else { return }
        if now >= next { scanAll() }
    }

    // MARK: - Dev-folder projects

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

    // MARK: - Selection

    /// Reset the selection to exactly the safe, cleanable targets —
    /// dropping any previously ticked Caution/Destructive targets and
    /// dev-folder artifacts — so the overview's "Reclaim safe space"
    /// confirms only what it names.
    public func selectOnlySafe() {
        selection.clear()
        projects.clearArtifactSelection()
        selection.selectAllSafe()
    }

    // MARK: - Scanning

    /// Scan every target with bounded parallelism.
    public func scanAll() {
        guard !activity.isScanning, !activity.isCleaning else { return }
        activity.isScanning = true
        activity.isCancellingScan = false
        selection.clearForScan()
        activity.lastCleanSummary = nil
        breakdowns.invalidateAll()
        projects.resetForScan()
        results.scanRealRoots.removeAll()
        activity.scanProgress = ScanProgress(
            completed: 0, total: results.targets.count + projects.devRoots.count,
            currentTargetName: "", currentPath: ""
        )
        for target in results.targets {
            results.setStatus(.scanning, for: target.id)
        }

        let probe = fullDiskAccessProbe
        scanTask = Task { [targets = results.targets] in
            // Keep the process off App Nap for the duration: a scan with
            // the window closed (menu-bar-only) would otherwise be
            // throttled, and the weekly background scan is exactly that
            // case.
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated], reason: "Scanning for reclaimable storage"
            )
            defer { ProcessInfo.processInfo.endActivity(activity) }
            self.results.hasFullDiskAccess = await offMain { probe() }
            await self.runScan(of: targets)
            // Any rows still marked scanning were cancelled mid-flight.
            for target in targets where self.results.statuses[target.id] == .scanning {
                self.results.setStatus(.idle, for: target.id)
            }
            await self.runProjectScan()
            self.results.lastScan = .now
            self.results.lastScanWasComplete = !Task.isCancelled
            // Only a completed scan anchors the weekly schedule — a scan
            // the user stopped after two seconds must not push the next
            // automatic scan a full week out.
            if !Task.isCancelled {
                self.lastCompletedScanDate = .now
                self.defaults.set(Date.now, forKey: DefaultsKey.lastScanDate)
            }
            self.activity.isScanning = false
            self.activity.isCancellingScan = false
            self.activity.scanProgress = nil
            self.scanTask = nil
            self.applyPostScanSelection()
            self.results.refreshVolumeSpace()
        }
    }

    /// Mirrors the design's post-scan behavior: Safe items come ticked
    /// (plus Caution when the setting opts in), so one click cleans.
    /// Targets the user excluded from automatic selection stay unticked.
    private func applyPostScanSelection() {
        for target in results.targets where selection.isSelectable(target) {
            guard !selection.isExcludedFromAutoSelect(target) else { continue }
            let wanted = target.safety == .safe
                || (settings.preselectCaution && target.safety == .caution)
            if wanted {
                selection.insertForPostScan(target.id)
            }
        }
    }

    public func cancelScan() {
        guard scanTask != nil else { return }
        activity.isCancellingScan = true
        scanTask?.cancel()
    }

    /// Stop the running clean pass after the in-flight target finishes.
    public func cancelClean() {
        guard cleanTask != nil else { return }
        activity.isCancellingClean = true
        cleanTask?.cancel()
    }

    /// Prepare for app termination: stop any in-flight clean pass and
    /// wait for it to unwind so the summary is shown and the history is
    /// persisted before the process exits. The in-flight target always
    /// finishes (cancellation is checked between jobs), so nothing is
    /// left half-cleaned, and every completed removal is recorded. Safe
    /// to call when nothing is running — it returns at once.
    public func prepareForTermination() async {
        if cleanTask != nil {
            activity.isCancellingClean = true
            cleanTask?.cancel()
            _ = await cleanTask?.value
        }
        // record(from:duration:freeAfterBytes:) (run at the end of the
        // pass) schedules the persist; await it so the on-disk history
        // is up to date.
        await history.flush()
    }

    /// Fan out scans through a width-limited task group. Runs on the
    /// main actor; the blocking work happens inside the child tasks,
    /// which execute nonisolated on the global executor.
    private func runScan(of targets: [CleanupTarget]) async {
        let scan = scanExecutor
        await withTaskGroup(of: (CleanupTarget.ID, TargetStatus, Set<String>).self) { group in
            var pending = targets.makeIterator()
            var completed = 0
            // Started but not yet finished, oldest first. The head is
            // the longest-running walk — the honest thing for the
            // progress line to show while several run concurrently.
            var inFlight: [CleanupTarget] = []

            // Nested functions do not inherit the enclosing actor, so
            // spell out the isolation these need to touch progress.
            @MainActor
            func publishProgress() {
                let current = inFlight.first
                activity.scanProgress = ScanProgress(
                    completed: completed,
                    total: targets.count + projects.devRoots.count,
                    currentTargetName: current?.name ?? "",
                    currentPath: current.map(Self.displayLocation(of:)) ?? ""
                )
            }

            @MainActor
            @discardableResult
            func startNext() -> Bool {
                guard let target = pending.next() else { return false }
                inFlight.append(target)
                group.addTask {
                    let status = scan(target)
                    // Resolve the roots' real paths in the worker (off
                    // the main actor) so cleaning can later refuse a
                    // cleanup path whose ancestry was swapped for a
                    // symlink after the scan.
                    let real: Set<String>
                    if case .measured(_, let roots, _) = status {
                        real = Set(roots.map { $0.resolvingSymlinksInPath().path })
                    } else {
                        real = []
                    }
                    return (target.id, status, real)
                }
                return true
            }

            for _ in 0..<Self.maxConcurrentScans {
                startNext()
            }
            publishProgress()
            while let (id, resolvedStatus, realRoots) = await group.next() {
                results.setStatus(resolvedStatus, for: id)
                if realRoots.isEmpty {
                    results.scanRealRoots[id] = nil
                } else {
                    results.scanRealRoots[id] = realRoots
                }
                completed += 1
                inFlight.removeAll { $0.id == id }
                startNext()
                publishProgress()
            }
        }
    }

    /// Fan dev-root discovery through the same width-limited pattern as
    /// target scans, continuing the same progress counter.
    private func runProjectScan() async {
        let roots = projects.devRoots
        guard !roots.isEmpty, !Task.isCancelled else { return }
        let scan = projectScanExecutor
        let baseCompleted = results.targets.count

        await withTaskGroup(of: (DevRootScan, String).self) { group in
            var pending = roots.makeIterator()
            var completed = 0
            var inFlight: [URL] = []

            @MainActor
            func publishProgress() {
                let current = inFlight.first
                activity.scanProgress = ScanProgress(
                    completed: baseCompleted + completed,
                    total: results.targets.count + roots.count,
                    currentTargetName: current?.lastPathComponent ?? "",
                    currentPath: current.map {
                        ($0.path as NSString).abbreviatingWithTildeInPath
                    } ?? ""
                )
            }

            @MainActor
            @discardableResult
            func startNext() -> Bool {
                guard let root = pending.next() else { return false }
                inFlight.append(root)
                // Resolve the root's real path in the worker so artifact
                // cleaning can refuse anything whose parent no longer
                // resolves inside a scanned dev root.
                group.addTask { (scan(root), root.resolvingSymlinksInPath().path) }
                return true
            }

            for _ in 0..<Self.maxConcurrentScans {
                startNext()
            }
            publishProgress()
            while let (result, realRoot) = await group.next() {
                projects.recordScan(result, realRoot: realRoot)
                completed += 1
                inFlight.removeAll { $0.path == result.root.path }
                startNext()
                publishProgress()
            }
        }
    }

    /// Tilde-form location shown while a target is being processed.
    private nonisolated static func displayLocation(of target: CleanupTarget) -> String {
        if let pattern = target.pathPatterns.first { return pattern }
        if case .command(let spec) = target.strategy { return spec.displayCommand }
        return target.name
    }

    // MARK: - Cleaning

    private struct CleanJob {
        let target: CleanupTarget
        let paths: [URL]
        let bytesBefore: Int64
        /// What the (possibly partial) selection is expected to free —
        /// dry-run projection only; real passes measure.
        let estimatedBytes: Int64
    }

    private struct ArtifactCleanJob {
        let artifact: DiscoveredArtifact
        let projectName: String
        let devRoot: URL
    }

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

        activity.isCleaning = true
        activity.isCancellingClean = false
        let chosenDisposal = settings.disposal
        let scan = scanExecutor
        let clean = cleanExecutor
        let volume = volumeProbe

        cleanTask = Task {
            // A clean pass must not be throttled or napped part-way — hold
            // an activity assertion for its whole duration.
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated], reason: "Cleaning reclaimable storage"
            )
            defer { ProcessInfo.processInfo.endActivity(activity) }
            let passStart = Date.now
            var summary = CleanSummary(disposal: chosenDisposal)

            // Sequential on purpose: cleanup should be predictable and
            // easy to interrupt, and it is I/O-bound anyway. The
            // cancellation check sits between jobs: the in-flight
            // target always finishes, so nothing is left half-cleaned.
            for (index, job) in jobs.enumerated() {
                if Task.isCancelled {
                    summary.wasStopped = true
                    break
                }
                self.activity.cleanProgress = CleanProgress(
                    targetName: job.target.name,
                    targetPath: job.target.pathPatterns.first,
                    index: index + 1,
                    total: jobs.count + artifactJobs.count
                )
                self.results.setStatus(.scanning, for: job.target.id)

                // Refuse any cleanup path whose ancestry no longer
                // resolves to its scan-time root — a cache directory
                // swapped for a symlink after the scan would otherwise
                // redirect deletion outside the target.
                let allowedRoots = self.results.scanRealRoots[job.target.id] ?? []
                let pathsAreChildren: Bool
                if case .removeContents = job.target.strategy {
                    pathsAreChildren = true
                } else {
                    pathsAreChildren = false
                }
                let (safePaths, refusedPaths) = await offMain {
                    Self.partitionSafe(
                        job.paths,
                        allowedRealRoots: allowedRoots,
                        pathsAreChildren: pathsAreChildren
                    )
                }
                var outcome = await offMain {
                    clean(job.target, safePaths, chosenDisposal)
                }
                for refused in refusedPaths {
                    outcome.failures.append(CleanFailure(
                        path: refused.path,
                        message: localized(
                            "clean.pathChanged",
                            defaultValue: "Its location changed since the scan, so it was left untouched."
                        )
                    ))
                }
                summary.itemsRemoved += outcome.removedItems
                if outcome.removedItems > 0 {
                    summary.cleanedTargets += 1
                } else if !outcome.failures.isEmpty {
                    summary.failedTargets += 1
                }
                summary.failures.append(contentsOf: outcome.failures.map {
                    localized(
                        "clean.failureLine",
                        defaultValue: "\(job.target.name) — \($0.message)"
                    )
                })

                let refreshed = await offMain { scan(job.target) }
                self.results.setStatus(refreshed, for: job.target.id)
                self.breakdowns.invalidate(job.target.id)
                // Freed space is only credited when this pass actually
                // removed something *and* the rescan could measure it.
                // A target the tool pruned itself between scan and clean
                // (or one whose disposals all failed) must not be
                // reported as space Reclaim reclaimed — command targets
                // and failed rescans report "unknown", never a guess.
                let freed = refreshed.bytes.map { max(0, job.bytesBefore - $0) }
                if outcome.removedItems > 0 {
                    summary.reclaimedBytes += freed ?? 0
                    summary.cleaned.append(CleanSummary.CleanedTarget(
                        id: job.target.id,
                        name: job.target.name,
                        category: job.target.category,
                        bytesFreed: freed,
                        bytesAfter: refreshed.bytes
                    ))
                }
                self.selection.removeAfterClean(job.target.id)
            }

            // Dev-folder artifacts, after the registry targets. Same
            // sequential, cancellable, best-effort discipline.
            let removeArtifacts = self.artifactCleanExecutor
            var cleanedRoots: [URL] = []
            for (offset, job) in artifactJobs.enumerated() {
                if Task.isCancelled {
                    summary.wasStopped = true
                    break
                }
                let name = self.projects.artifactDisplayName(
                    kindID: job.artifact.kindID, projectName: job.projectName
                )
                self.activity.cleanProgress = CleanProgress(
                    targetName: name,
                    targetPath: (job.artifact.url.path as NSString).abbreviatingWithTildeInPath,
                    index: jobs.count + offset + 1,
                    total: jobs.count + artifactJobs.count
                )

                let url = job.artifact.url
                // Same scan-time pin as registry targets: only dispose
                // of the artifact while its parent still resolves inside
                // a scanned dev root.
                let devRootsSnapshot = self.projects.scanRealDevRoots
                let pinHolds = await offMain {
                    Self.artifactPinHolds(url, allowedRealDevRoots: devRootsSnapshot)
                }
                let outcome: CleanOutcome
                if pinHolds {
                    outcome = await offMain {
                        removeArtifacts([url], chosenDisposal)
                    }
                } else {
                    outcome = CleanOutcome(failures: [CleanFailure(
                        path: url.path,
                        message: localized(
                            "clean.pathChanged",
                            defaultValue: "Its location changed since the scan, so it was left untouched."
                        )
                    )])
                }
                summary.itemsRemoved += outcome.removedItems
                summary.failures.append(contentsOf: outcome.failures.map {
                    localized(
                        "clean.failureLine",
                        defaultValue: "\(name) — \($0.message)"
                    )
                })

                // Freed space is only credited when this pass actually
                // removed the artifact *and* it is verifiably gone from
                // disk. An artifact deleted out from under us between
                // scan and clean (a build tool, another cleaner) fails
                // the removal — its bytes are not space Reclaim freed.
                if outcome.removedItems > 0 {
                    let gone = await offMain {
                        !FileManager.default.fileExists(atPath: url.path)
                    }
                    let freed: Int64? = gone ? job.artifact.measurement.bytes : nil
                    summary.reclaimedBytes += freed ?? 0
                    summary.cleanedTargets += 1
                    summary.cleanedArtifacts.append(CleanSummary.CleanedArtifact(
                        id: job.artifact.id, name: name, bytesFreed: freed
                    ))
                    if !cleanedRoots.contains(where: { $0.path == job.devRoot.path }) {
                        cleanedRoots.append(job.devRoot)
                    }
                } else if !outcome.failures.isEmpty {
                    summary.failedTargets += 1
                }
                self.projects.removeFromSelection(job.artifact.id)
            }

            // Re-discover the affected roots so the Projects list stays
            // truthful — reclaimed space is measured, never assumed.
            let rescan = self.projectScanExecutor
            for root in cleanedRoots {
                let refreshed = await offMain { rescan(root) }
                self.projects.replaceScan(refreshed)
            }

            self.activity.cleanProgress = nil
            self.activity.lastCleanSummary = summary
            self.activity.isCleaning = false
            self.activity.isCancellingClean = false
            self.cleanTask = nil
            // Volume space is measured before recording, so the entry
            // carries the honest "free after this clean" figure.
            let space = await offMain { volume() }
            self.results.volumeSpace = space
            self.history.record(
                from: summary,
                duration: Date.now.timeIntervalSince(passStart),
                freeAfterBytes: space?.availableBytes
            )
        }
    }

    // MARK: - Background helpers

    /// Split scan-time cleanup paths into those still safe to dispose
    /// and those whose ancestry changed since the scan.
    ///
    /// `allowedRealRoots` is the symlink-resolved form of the target's
    /// roots at scan time. For `.removeContents` each path is a child of
    /// a root, so its *parent* must still resolve to one of those roots;
    /// for `.removePaths` each path *is* a root. An empty set means the
    /// scan captured no pin (e.g. a command target), so the paths pass
    /// straight through to the engine's own exclusion guard.
    private nonisolated static func partitionSafe(
        _ paths: [URL], allowedRealRoots: Set<String>, pathsAreChildren: Bool
    ) -> (safe: [URL], refused: [URL]) {
        guard !allowedRealRoots.isEmpty else { return (paths, []) }
        var safe: [URL] = []
        var refused: [URL] = []
        for path in paths {
            let container = pathsAreChildren ? path.deletingLastPathComponent() : path
            if allowedRealRoots.contains(container.resolvingSymlinksInPath().path) {
                safe.append(path)
            } else {
                refused.append(path)
            }
        }
        return (safe, refused)
    }

    /// True while the artifact's parent still resolves inside a scanned
    /// dev root — the same scan-time pin as ``partitionSafe(_:allowedRealRoots:pathsAreChildren:)``,
    /// for dev-folder artifacts, which have no registry root.
    private nonisolated static func artifactPinHolds(
        _ url: URL, allowedRealDevRoots: Set<String>
    ) -> Bool {
        guard !allowedRealDevRoots.isEmpty else { return true }
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        return allowedRealDevRoots.contains { parent == $0 || parent.hasPrefix($0 + "/") }
    }

    // MARK: - Preview support

    #if DEBUG
    /// Preview-only: install canned scan results so SwiftUI previews
    /// can render every screen without touching the filesystem.
    public func seedForPreview(
        statuses: [CleanupTarget.ID: TargetStatus],
        selection: Set<CleanupTarget.ID> = [],
        history: [CleanHistoryEntry] = [],
        breakdowns: [CleanupTarget.ID: [BreakdownEntry]] = [:],
        volumeSpace: VolumeSpace? = nil,
        hasFullDiskAccess: Bool? = true,
        lastCleanSummary: CleanSummary? = nil
    ) {
        self.results.statuses = statuses
        self.selection.seed(ids: selection)
        self.history.seed(entries: history)
        self.breakdowns.seed(entries: breakdowns)
        self.results.volumeSpace = volumeSpace
        self.results.hasFullDiskAccess = hasFullDiskAccess
        self.activity.lastCleanSummary = lastCleanSummary
        self.results.lastScan = .now
        self.results.lastScanWasComplete = true
    }

    /// Preview-only: canned dev-folder discovery without touching
    /// UserDefaults persistence or running a scan.
    public func seedProjectsForPreview(devRoots: [URL], projectScans: [DevRootScan]) {
        projects.seed(devRoots: devRoots, projectScans: projectScans)
    }
    #endif
}
