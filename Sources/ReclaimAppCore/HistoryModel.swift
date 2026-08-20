//
//  HistoryModel.swift
//  ReclaimAppCore
//
//  Persistent clean history, split out of AppModel so the god class
//  sheds its persistence plumbing while behavior stays identical.
//

import Foundation
import Observation
import ReclaimKit

@Observable
public final class HistoryModel {
    /// Past clean passes, newest first.
    public private(set) var entries: [CleanHistoryEntry]

    @ObservationIgnored
    private let historyStore: CleanHistoryStore

    /// Chains history saves so a later write can never lose to an
    /// earlier one still in flight.
    @ObservationIgnored
    private var historyPersistTask: Task<Void, Never>?

    public init(store: CleanHistoryStore) {
        self.historyStore = store
        self.entries = store.load().sorted { $0.date > $1.date }
    }

    /// All-time reclaimed space across recorded cleans.
    public var reclaimedAllTimeBytes: Int64 {
        entries.reduce(0) { $0 + $1.reclaimedBytes }
    }

    /// Append a real pass with removals to the persistent history.
    func record(
        from summary: CleanSummary, duration: TimeInterval, freeAfterBytes: Int64?
    ) {
        guard !summary.isDryRun, summary.itemsRemoved > 0 else { return }
        let entry = CleanHistoryEntry(
            date: .now,
            targetNames: summary.cleaned.map(\.name) + summary.cleanedArtifacts.map(\.name),
            itemsRemoved: summary.itemsRemoved,
            reclaimedBytes: summary.reclaimedBytes,
            items: summary.cleaned.map {
                CleanedHistoryItem(
                    targetID: $0.id, name: $0.name,
                    bytesFreed: $0.bytesFreed, bytesAfter: $0.bytesAfter
                )
            } + summary.cleanedArtifacts.map {
                CleanedHistoryItem(
                    targetID: "artifact:\($0.id)", name: $0.name,
                    bytesFreed: $0.bytesFreed
                )
            },
            disposal: summary.disposal,
            duration: duration,
            freeAfterBytes: freeAfterBytes
        )
        entries.insert(entry, at: 0)
        persistHistory()
    }

    /// Record that the user emptied the Trash through Reclaim. Emptying
    /// is global, so every trash-disposal pass still unmarked gets the
    /// stamp — their files all left the Trash together.
    public func markTrashEmptied(at date: Date = .now) {
        var changed = false
        for index in entries.indices
        where entries[index].disposal == .trash && entries[index].trashEmptiedDate == nil {
            entries[index].trashEmptiedDate = date
            changed = true
        }
        if changed { persistHistory() }
    }

    /// Erase the recorded clean history. Files on disk are unaffected.
    public func clear() {
        entries.removeAll()
        persistHistory()
    }

    /// Saves are chained so a clear issued right after a clean pass can
    /// never lose the race against the pass's own (earlier) save.
    private func persistHistory() {
        let store = historyStore
        let snapshot = entries
        let previous = historyPersistTask
        historyPersistTask = Task {
            await previous?.value
            await Self.persist(store, snapshot)
        }
    }

    /// Writes the history snapshot on the concurrent executor — the
    /// blocking filesystem boundary of a save.
    @concurrent
    private static func persist(_ store: CleanHistoryStore, _ snapshot: [CleanHistoryEntry]) async {
        store.save(snapshot)
    }

    /// Await the persist chain — called at app termination so the on-disk
    /// history is up to date before the process exits.
    func flush() async {
        _ = await historyPersistTask?.value
    }

    // MARK: - Preview support

    #if DEBUG
    /// Preview-only: install canned history entries so SwiftUI previews
    /// can render every screen without touching the filesystem.
    func seed(entries: [CleanHistoryEntry]) {
        self.entries = entries
    }
    #endif
}
