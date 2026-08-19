//
//  SelectionModel.swift
//  ReclaimAppCore
//
//  What the user has ticked for cleaning — whole-target selection plus
//  the auto-select exclusions — split out of AppModel so the god class
//  sheds its selection plumbing while behavior stays identical. Every
//  eligibility rule reads live scan results and pass flags from the
//  models this one is given; the cherry-picking half of the API lives
//  in SelectionModel+CherryPicking.swift, which mutates the state
//  declared here (stored properties cannot live in an extension).
//

import Foundation
import Observation
import ReclaimKit

@MainActor
@Observable
public final class SelectionModel {
    // MARK: - Session state

    /// Targets the user has ticked for cleaning.
    public internal(set) var ids: Set<CleanupTarget.ID> = []

    /// Cherry-picked cleanup paths per target (path → scan-time bytes
    /// from the contents breakdown). A target with an entry here is
    /// *partially* selected: cleaning disposes only these paths. A
    /// selected target without an entry cleans everything.
    public internal(set) var partialSelections: [CleanupTarget.ID: [String: Int64]] = [:]

    /// Target ids the user chose to keep out of automatic selection
    /// (the post-scan preselection and "select all safe"). Ticking them
    /// manually still works. Persisted across launches.
    public private(set) var autoSelectExclusions: Set<CleanupTarget.ID>

    @ObservationIgnored
    let results: TargetResultsModel
    @ObservationIgnored
    let activity: ActivityModel
    @ObservationIgnored
    let breakdowns: BreakdownModel

    @ObservationIgnored
    private let defaults: UserDefaults

    private enum DefaultsKey {
        static let autoSelectExclusions = "settings.autoSelectExclusions"
    }

    // MARK: - Init

    public init(
        results: TargetResultsModel,
        activity: ActivityModel,
        breakdowns: BreakdownModel,
        defaults: UserDefaults
    ) {
        self.results = results
        self.activity = activity
        self.breakdowns = breakdowns
        self.defaults = defaults
        self.autoSelectExclusions = Set(
            defaults.stringArray(forKey: DefaultsKey.autoSelectExclusions) ?? []
        )
    }

    // MARK: - Selection

    /// Whether the row's checkbox is enabled.
    public func isSelectable(_ target: CleanupTarget) -> Bool {
        guard target.strategy.isCleanable, !activity.isScanning, !activity.isCleaning else { return false }
        switch results.status(of: target.id) {
        case .measured(let measurement, _, _): return measurement.bytes > 0
        case .unmeasurable: return true
        default: return false
        }
    }

    public func isSelected(_ target: CleanupTarget) -> Bool {
        ids.contains(target.id)
    }

    /// The selected targets, in registry order.
    public var selectedTargets: [CleanupTarget] {
        results.targets.filter { ids.contains($0.id) }
    }

    /// How many targets could be ticked right now — the denominator for
    /// "N of M selected". Manual-only targets never count.
    public var selectableItemCount: Int {
        selectableItemCount(among: results.targets)
    }

    /// The same count restricted to a subset (one browser view's list).
    public func selectableItemCount(among candidates: [CleanupTarget]) -> Int {
        candidates.count { target in
            guard target.strategy.isCleanable else { return false }
            switch results.status(of: target.id) {
            case .measured(let measurement, _, _): return measurement.bytes > 0
            case .unmeasurable: return true
            default: return false
            }
        }
    }

    public func isExcludedFromAutoSelect(_ target: CleanupTarget) -> Bool {
        autoSelectExclusions.contains(target.id)
    }

    /// Keep a target out of (or return it to) automatic selection.
    /// Excluding a currently ticked target unticks it immediately.
    public func setExcludedFromAutoSelect(_ target: CleanupTarget, _ excluded: Bool) {
        if excluded {
            autoSelectExclusions.insert(target.id)
            ids.remove(target.id)
            partialSelections[target.id] = nil
        } else {
            autoSelectExclusions.remove(target.id)
        }
        defaults.set(autoSelectExclusions.sorted(), forKey: DefaultsKey.autoSelectExclusions)
    }

    /// Select (fully) or deselect a target. Either way any cherry-picked
    /// subset is discarded — this is the whole-target switch.
    public func setSelected(_ target: CleanupTarget, _ selected: Bool) {
        partialSelections[target.id] = nil
        if selected, isSelectable(target) {
            ids.insert(target.id)
        } else {
            ids.remove(target.id)
        }
    }

    /// Select every selectable target rated ``SafetyLevel/safe``,
    /// honoring the user's auto-select exclusions.
    public func selectAllSafe() {
        for target in results.targets where target.safety == .safe
            && isSelectable(target)
            && !autoSelectExclusions.contains(target.id) {
            ids.insert(target.id)
            partialSelections[target.id] = nil
        }
    }

    public func clear() {
        ids.removeAll()
        partialSelections.removeAll()
    }

    // MARK: - Pass seams

    /// A starting scan drops the whole selection, cherry-picks included:
    /// nothing measured before the pass survives it.
    func clearForScan() {
        ids.removeAll()
        partialSelections.removeAll()
    }

    /// Untick a target once its clean job has run.
    func removeAfterClean(_ id: CleanupTarget.ID) {
        ids.remove(id)
        partialSelections[id] = nil
    }

    /// Tick a target as part of the post-scan preselection. Partials are
    /// untouched — a fresh scan leaves none.
    func insertForPostScan(_ id: CleanupTarget.ID) {
        ids.insert(id)
    }

    // MARK: - Preview support

    #if DEBUG
    /// Preview-only: install a canned selection so SwiftUI previews can
    /// render every screen without touching the filesystem.
    func seed(ids: Set<CleanupTarget.ID>) {
        self.ids = ids
    }
    #endif
}
