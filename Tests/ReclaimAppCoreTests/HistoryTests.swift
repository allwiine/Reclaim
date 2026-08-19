//
//  HistoryTests.swift
//  ReclaimAppCoreTests
//
//  Orchestration-layer tests against stubbed scan/clean executors —
//  no filesystem, no Trash, deterministic.
//

import Foundation
import ReclaimKit
import Synchronization
import Testing
@testable import ReclaimAppCore

@MainActor
@Suite("History")
struct HistoryTests {
    @Test("A real clean pass is recorded in persistent history")
    func historyRecording() async {
        let store = TemporaryDefaults()
        let historyStore = temporaryHistoryStore()
        let cache = target("cache")
        let scanCount = Mutex(0)
        let model = AppModel(
            targets: [cache],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in
                    let calls = scanCount.withLock { $0 += 1; return $0 }
                    return calls == 1 ? measured(100) : measured(0)
                },
                clean: { _, _, _ in CleanOutcome(removedItems: 3) }
            ),
            historyStore: historyStore
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.cleaner.cleanSelected()
        await model.cleaner.cleanTask?.value

        #expect(model.history.entries.count == 1)
        #expect(model.history.entries.first?.targetNames == ["cache"])
        #expect(model.history.entries.first?.itemsRemoved == 3)
        #expect(model.history.entries.first?.reclaimedBytes == 100)
        #expect(model.history.reclaimedAllTimeBytes == 100)
        #expect(model.activity.lastCleanSummary?.cleaned.map(\.name) == ["cache"])

        // The entry must survive a fresh model (i.e. an app restart).
        for _ in 0..<10_000 where historyStore.load().isEmpty {
            await Task.yield()
        }
        #expect(historyStore.load().count == 1)
    }

    @Test("History entries carry the detail the history pane shows")
    func historyDetailRecording() async {
        let store = TemporaryDefaults()
        let cache = target("cache")
        let scanCount = Mutex(0)
        let model = AppModel(
            targets: [cache],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in
                    let calls = scanCount.withLock { $0 += 1; return $0 }
                    return calls == 1 ? measured(100) : measured(0)
                },
                clean: { _, _, _ in CleanOutcome(removedItems: 2) },
                volume: {
                    VolumeSpace(totalBytes: 1_000, availableBytes: 400, localizedName: "Test")
                }
            ),
            historyStore: temporaryHistoryStore()
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.cleaner.cleanSelected()
        await model.cleaner.cleanTask?.value

        let entry = model.history.entries.first
        #expect(entry?.items?.map(\.targetID) == ["cache"])
        #expect(entry?.items?.first?.bytesFreed == 100)
        #expect(entry?.items?.first?.bytesAfter == 0, "a full clean leaves a zero baseline")
        #expect(entry?.disposal == .trash)
        #expect(entry?.duration != nil)
        #expect(entry?.freeAfterBytes == 400, "free space is measured right after the pass")
        #expect(entry?.trashEmptiedDate == nil, "emptying is only known when done through Reclaim")
    }

    @Test("Emptying the Trash stamps every unmarked trash pass")
    func trashEmptiedStamping() async {
        let store = TemporaryDefaults()
        let historyStore = temporaryHistoryStore()
        let cache = target("cache")
        let scanCount = Mutex(0)
        let model = AppModel(
            targets: [cache],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in
                    let calls = scanCount.withLock { $0 += 1; return $0 }
                    return calls % 2 == 1 ? measured(100) : measured(0)
                },
                clean: { _, _, _ in CleanOutcome(removedItems: 1) }
            ),
            historyStore: historyStore
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.cleaner.cleanSelected()
        await model.cleaner.cleanTask?.value
        #expect(model.history.entries.first?.trashEmptiedDate == nil)

        // Whole seconds: the store's ISO8601 coding drops fractions.
        let emptied = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded())
        model.history.markTrashEmptied(at: emptied)
        #expect(model.history.entries.first?.trashEmptiedDate == emptied)

        // Idempotent: a later emptying never rewrites an earlier stamp.
        model.history.markTrashEmptied(at: emptied.addingTimeInterval(3_600))
        #expect(model.history.entries.first?.trashEmptiedDate == emptied)

        // Permanent-delete passes are never stamped.
        model.settings.disposal = .delete
        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.selection.setSelected(cache, true)
        model.cleaner.cleanSelected()
        await model.cleaner.cleanTask?.value
        model.history.markTrashEmptied()
        #expect(model.history.entries.first?.disposal == .delete)
        #expect(model.history.entries.first?.trashEmptiedDate == nil)

        // The stamps persist.
        for _ in 0..<10_000 where historyStore.load().count < 2 {
            await Task.yield()
        }
        #expect(historyStore.load().last?.trashEmptiedDate == emptied)
    }

    @Test("Clearing history empties memory and the persistent store")
    func clearHistory() async {
        let store = TemporaryDefaults()
        let historyStore = temporaryHistoryStore()
        let scanCount = Mutex(0)
        let model = AppModel(
            targets: [target("cache")],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in
                    let calls = scanCount.withLock { $0 += 1; return $0 }
                    return calls == 1 ? measured(100) : measured(0)
                },
                clean: { _, _, _ in CleanOutcome(removedItems: 1) }
            ),
            historyStore: historyStore
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.cleaner.cleanSelected()
        await model.cleaner.cleanTask?.value
        #expect(model.history.entries.count == 1)

        // Clearing immediately after the pass must win against the
        // pass's own save still in flight.
        model.history.clear()
        #expect(model.history.entries.isEmpty)
        #expect(model.history.reclaimedAllTimeBytes == 0)

        for _ in 0..<10_000 where !historyStore.load().isEmpty {
            await Task.yield()
        }
        #expect(historyStore.load().isEmpty, "the cleared state must be what persists")
    }
}
