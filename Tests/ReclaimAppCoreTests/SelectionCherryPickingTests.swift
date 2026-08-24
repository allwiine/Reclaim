//
//  SelectionCherryPickingTests.swift
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

@Suite("Selection — cherry-picking")
struct SelectionCherryPickingTests {
    @Test("Cherry-picking paths drives partial selection state")
    func pathCherryPicking() async {
        let store = TemporaryDefaults()
        let cache = target("cache")
        let cleanupPaths = [URL(filePath: "/fixture/a"), URL(filePath: "/fixture/b")]
        let model = AppModel(
            targets: [cache],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100, cleanupPaths: cleanupPaths) },
                breakdown: { _ in
                    [
                        BreakdownEntry(id: "/fixture/a", name: "a", bytes: 60),
                        BreakdownEntry(id: "/fixture/b", name: "b", bytes: 40),
                    ]
                }
            ),
            historyStore: temporaryHistoryStore()
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        #expect(model.selection.isSelected(cache), "safe target arrives fully selected")
        model.breakdowns.load(for: cache)
        for _ in 0..<10_000 where model.breakdowns.entries["cache"] == nil {
            await Task.yield()
        }

        // Untick one path: full → partial.
        model.selection.setPathSelected(cache, path: "/fixture/a", false)
        #expect(model.selection.isSelected(cache))
        #expect(model.selection.isPartiallySelected(cache))
        #expect(model.selection.partialSelectionCounts(of: cache)?.selected == 1)
        #expect(model.selection.partialSelectionCounts(of: cache)?.total == 2)
        #expect(model.selection.selectedBytes(of: cache) == 40, "subset bytes come from the breakdown")
        #expect(model.selectedBytes == 40)
        #expect(model.selection.selectedCleanupPaths(of: cache).map(\.path) == ["/fixture/b"])
        #expect(!model.selection.isPathSelected(cache, path: "/fixture/a"))
        #expect(model.selection.isPathSelected(cache, path: "/fixture/b"))

        // Untick the last path: partial → deselected.
        model.selection.setPathSelected(cache, path: "/fixture/b", false)
        #expect(!model.selection.isSelected(cache))
        #expect(!model.selection.isPartiallySelected(cache))

        // Tick one path from nothing: deselected → partial.
        model.selection.setPathSelected(cache, path: "/fixture/a", true)
        #expect(model.selection.isPartiallySelected(cache))
        #expect(model.selection.selectedBytes(of: cache) == 60)

        // Tick the rest: partial folds back into full selection.
        model.selection.setPathSelected(cache, path: "/fixture/b", true)
        #expect(model.selection.isSelected(cache))
        #expect(!model.selection.isPartiallySelected(cache))
        #expect(model.selection.selectedBytes(of: cache) == 100)

        // The whole-target switch always discards the subset.
        model.selection.setPathSelected(cache, path: "/fixture/a", false)
        model.selection.setSelected(cache, true)
        #expect(!model.selection.isPartiallySelected(cache))
        #expect(model.selection.selectedBytes(of: cache) == 100)
    }

    @Test("A partial selection cleans only the ticked paths")
    func partialSelectionCleansSubset() async {
        let store = TemporaryDefaults()
        let cache = target("cache")
        let cleanupPaths = [URL(filePath: "/fixture/a"), URL(filePath: "/fixture/b")]
        let cleanedPaths = Mutex<[URL]>([])
        let scanCount = Mutex(0)
        let model = AppModel(
            targets: [cache],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in
                    let calls = scanCount.withLock { $0 += 1; return $0 }
                    return calls == 1 ? measured(100, cleanupPaths: cleanupPaths) : measured(60)
                },
                clean: { _, paths, _ in
                    cleanedPaths.withLock { $0 = paths }
                    return CleanOutcome(removedItems: paths.count)
                },
                breakdown: { _ in
                    [
                        BreakdownEntry(id: "/fixture/a", name: "a", bytes: 60),
                        BreakdownEntry(id: "/fixture/b", name: "b", bytes: 40),
                    ]
                }
            ),
            historyStore: temporaryHistoryStore()
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.breakdowns.load(for: cache)
        for _ in 0..<10_000 where model.breakdowns.entries["cache"] == nil {
            await Task.yield()
        }
        model.selection.setPathSelected(cache, path: "/fixture/a", false)

        // Dry run projects the subset, not the whole target.
        model.settings.dryRun = true
        model.cleaner.cleanSelected()
        #expect(model.activity.lastCleanSummary?.reclaimedBytes == 40)
        #expect(model.activity.lastCleanSummary?.itemsRemoved == 1)
        #expect(model.selection.isPartiallySelected(cache), "a dry run leaves the picks alone")
        model.settings.dryRun = false

        model.cleaner.cleanSelected()
        await model.cleaner.cleanTask?.value
        #expect(cleanedPaths.withLock { $0 }.map(\.path) == ["/fixture/b"],
                "the engine must receive only the ticked path")
        #expect(!model.selection.isPartiallySelected(cache), "picks are consumed by the pass")
        #expect(model.activity.lastCleanSummary?.reclaimedBytes == 40, "freed is measured by the rescan")
        #expect(
            model.history.entries.first?.items?.first?.bytesAfter == 60,
            "the remainder is recorded so it never counts as regrowth"
        )
        #expect(model.history.entries.first?.items?.first?.bytesFreed == 40)
    }
}
