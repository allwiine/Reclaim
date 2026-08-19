//
//  SelectionModel+CherryPicking.swift
//  ReclaimAppCore
//
//  Picking individual scan-time cleanup paths inside a selected target,
//  and the sizes those picks cover. Split out of AppModel together with
//  the rest of the selection; the state it reads and writes is declared
//  on ``SelectionModel`` itself.
//

import Foundation
import ReclaimKit

extension SelectionModel {
    // MARK: - Cherry-picking

    public func isPartiallySelected(_ target: CleanupTarget) -> Bool {
        partialSelections[target.id] != nil
    }

    /// (ticked, total) cleanup-path counts, when partially selected.
    public func partialSelectionCounts(of target: CleanupTarget) -> (selected: Int, total: Int)? {
        guard let partial = partialSelections[target.id] else { return nil }
        return (partial.count, results.status(of: target.id).cleanupPaths.count)
    }

    /// Whether one scan-time cleanup path is in the effective clean scope.
    public func isPathSelected(_ target: CleanupTarget, path: String) -> Bool {
        guard ids.contains(target.id) else { return false }
        guard let partial = partialSelections[target.id] else { return true }
        return partial[path] != nil
    }

    /// Tick or untick a single scan-time cleanup path. Ticking the last
    /// missing path folds back into full selection; unticking the last
    /// ticked one deselects the target entirely.
    public func setPathSelected(_ target: CleanupTarget, path: String, _ on: Bool) {
        guard target.strategy.isCleanable, !activity.isScanning, !activity.isCleaning else { return }
        let allPaths = results.status(of: target.id).cleanupPaths.map(\.path)
        guard allPaths.contains(path) else { return }

        var chosen: Set<String>
        if !ids.contains(target.id) {
            chosen = []
        } else if let partial = partialSelections[target.id] {
            chosen = Set(partial.keys)
        } else {
            chosen = Set(allPaths)
        }
        if on { chosen.insert(path) } else { chosen.remove(path) }

        if chosen.isEmpty {
            ids.remove(target.id)
            partialSelections[target.id] = nil
        } else if chosen.count == allPaths.count {
            guard isSelectable(target) else { return }
            ids.insert(target.id)
            partialSelections[target.id] = nil
        } else {
            guard isSelectable(target) else { return }
            ids.insert(target.id)
            // Sizes come from the contents breakdown, which is loaded
            // whenever the inspector (the only place that ticks paths)
            // is showing the target.
            let entries = breakdowns.entries[target.id] ?? []
            partialSelections[target.id] = chosen.reduce(into: [:]) { map, chosenPath in
                map[chosenPath] = entries.first { $0.id == chosenPath }?.bytes ?? 0
            }
        }
    }

    /// The exact paths a clean pass would dispose for this target now.
    public func selectedCleanupPaths(of target: CleanupTarget) -> [URL] {
        let all = results.status(of: target.id).cleanupPaths
        guard let partial = partialSelections[target.id] else { return all }
        return all.filter { partial.keys.contains($0.path) }
    }

    /// Bytes this target's current selection covers (subset-aware).
    public func selectedBytes(of target: CleanupTarget) -> Int64 {
        guard ids.contains(target.id) else { return 0 }
        if let partial = partialSelections[target.id] {
            return partial.values.reduce(0, +)
        }
        return results.status(of: target.id).bytes ?? 0
    }

    /// Scan-time size of one cleanup path, when the breakdown measured it.
    public func breakdownBytes(of target: CleanupTarget, path: String) -> Int64? {
        if let bytes = partialSelections[target.id]?[path] { return bytes }
        return breakdowns.entries[target.id]?.first { $0.id == path }?.bytes
    }
}
