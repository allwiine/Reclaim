//
//  AppModel.swift
//  ReclaimAppCore
//
//  The composition root the UI observes. It holds no session state of
//  its own: it wires the sub-models in dependency order, initializing
//  activity at its property declaration, then settings, results,
//  breakdowns, selection, projects, history, and the two coordinators
//  (scanner, cleaner) in the init. Lives in a UI-free library target
//  so the orchestration layer stays unit-testable; the scan/clean seams
//  are injected as `Executors`.
//
//  Only the handful of things no single sub-model owns live here: the
//  termination handshake, the "safe only" selection reset, and the
//  cross-model overview aggregates (AppModel+Overview.swift). The
//  concurrency model belongs to the work, not to this file — see
//  ScanCoordinator.swift and CleanCoordinator.swift for how each pass
//  moves blocking filesystem work off the main actor.
//

import Foundation
import Observation
import ReclaimKit

@Observable
public final class AppModel {
    // MARK: - Sub-models

    /// Per-target scan results and the totals derived from them.
    public let results: TargetResultsModel

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

    /// Scan orchestration and the weekly background schedule.
    public let scanner: ScanCoordinator

    /// The clean pass and its scan-time safety pins.
    public let cleaner: CleanCoordinator

    // MARK: - Settings

    /// UserDefaults-backed settings, split out of this model.
    public let settings: SettingsStore

    // MARK: - Init

    public init(
        targets: [CleanupTarget] = TargetRegistry.all,
        defaults: UserDefaults = .standard,
        executors: Executors = Executors(),
        historyStore: CleanHistoryStore = CleanHistoryStore()
    ) {
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
        self.history = HistoryModel(store: historyStore)
        // Last: the coordinators take every other model as a dependency.
        self.scanner = ScanCoordinator(
            executors: executors,
            results: results,
            selection: selection,
            projects: projects,
            breakdowns: breakdowns,
            settings: settings,
            activity: activity,
            defaults: defaults
        )
        self.cleaner = CleanCoordinator(
            executors: executors,
            results: results,
            selection: selection,
            projects: projects,
            breakdowns: breakdowns,
            settings: settings,
            activity: activity,
            history: history
        )
        results.refreshVolumeSpace()
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

    // MARK: - Termination

    /// Prepare for app termination: stop any in-flight clean pass and
    /// wait for it to unwind so the summary is shown and the history is
    /// persisted before the process exits. The in-flight target always
    /// finishes (cancellation is checked between jobs), so nothing is
    /// left half-cleaned, and every completed removal is recorded. Safe
    /// to call when nothing is running — it returns at once.
    public func prepareForTermination() async {
        if cleaner.cleanTask != nil {
            await cleaner.cancelAndWait()
        }
        // record(from:duration:freeAfterBytes:) (run at the end of the
        // pass) schedules the persist; await it so the on-disk history
        // is up to date.
        await history.flush()
    }
}
