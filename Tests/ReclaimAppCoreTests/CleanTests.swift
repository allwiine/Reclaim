//
//  CleanTests.swift
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
@Suite("Clean")
struct CleanTests {
    @Test("Cleaning disposes the scan-time cleanup paths and re-measures")
    func cleanUsesCleanupPaths() async {
        let store = TemporaryDefaults()
        let cache = target("cache")
        let cleanupPaths = [URL(filePath: "/fixture/a"), URL(filePath: "/fixture/b")]
        let scanCount = Mutex(0)
        let cleaned = Mutex<[(String, [URL], Disposal)]>([])

        let model = AppModel(
            targets: [cache],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in
                    // First scan sees 100 bytes; the post-clean rescan sees 0.
                    let calls = scanCount.withLock { $0 += 1; return $0 }
                    return calls == 1 ? measured(100, cleanupPaths: cleanupPaths) : measured(0)
                },
                clean: { t, paths, disposal in
                    cleaned.withLock { $0.append((t.id, paths, disposal)) }
                    return CleanOutcome(removedItems: paths.count)
                }
            ),
            historyStore: temporaryHistoryStore()
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.selection.setSelected(cache, true)
        model.cleaner.cleanSelected()
        await model.cleaner.cleanTask?.value

        let calls = cleaned.withLock { $0 }
        #expect(calls.count == 1)
        #expect(calls.first?.1 == cleanupPaths)
        #expect(calls.first?.2 == .trash)
        #expect(model.activity.isCleaning == false)
        #expect(model.selection.ids.isEmpty)
        #expect(model.activity.lastCleanSummary?.reclaimedBytes == 100)
        #expect(model.results.status(of: "cache").bytes == 0, "post-clean rescan must be reflected")
    }

    @Test("Summary counts only targets that actually had removals")
    func summaryAccuracy() async {
        let store = TemporaryDefaults()
        let ok = target("ok")
        let broken = target("broken")

        let model = AppModel(
            targets: [ok, broken],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) },
                clean: { t, _, _ in
                    t.id == "ok"
                        ? CleanOutcome(removedItems: 2)
                        : CleanOutcome(
                            removedItems: 0,
                            failures: [CleanFailure(path: "/x", message: "locked")]
                        )
                }
            ),
            historyStore: temporaryHistoryStore()
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.selection.setSelected(ok, true)
        model.selection.setSelected(broken, true)
        model.cleaner.cleanSelected()
        await model.cleaner.cleanTask?.value

        let summary = model.activity.lastCleanSummary
        #expect(summary?.itemsRemoved == 2)
        #expect(summary?.cleanedTargets == 1, "a target with zero removals was not cleaned")
        #expect(summary?.failedTargets == 1)
        #expect(summary?.failures.count == 1)
    }

    @Test("A target with removals and a locked file counts as cleaned, not failed")
    func mixedOutcomeCountsAsCleaned() async {
        let store = TemporaryDefaults()
        let partial = target("partial")
        let model = AppModel(
            targets: [partial],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) },
                clean: { _, _, _ in
                    CleanOutcome(
                        removedItems: 2,
                        failures: [CleanFailure(path: "/locked", message: "locked")]
                    )
                }
            ),
            historyStore: temporaryHistoryStore()
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.selection.setSelected(partial, true)
        model.cleaner.cleanSelected()
        await model.cleaner.cleanTask?.value

        let summary = model.activity.lastCleanSummary
        #expect(summary?.itemsRemoved == 2)
        #expect(summary?.cleanedTargets == 1, "≥1 removal means the target is cleaned")
        #expect(summary?.failedTargets == 0, "a partial success is not a failed target")
        #expect(summary?.failures.count == 1, "the locked file still surfaces")
    }

    @Test("A target-scoped clean cleans one target, the rest stays selected")
    func singleTargetClean() async {
        let store = TemporaryDefaults()
        let first = target("first")
        let second = target("second")
        let cleanedIDs = Mutex<[String]>([])
        let model = AppModel(
            targets: [first, second],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) },
                clean: { t, _, _ in
                    cleanedIDs.withLock { $0.append(t.id) }
                    return CleanOutcome(removedItems: 1)
                }
            ),
            historyStore: temporaryHistoryStore()
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        #expect(model.selection.isSelected(first) && model.selection.isSelected(second))

        model.cleaner.cleanSelected(scope: .targets([first.id]))
        await model.cleaner.cleanTask?.value

        #expect(cleanedIDs.withLock { $0 } == ["first"])
        #expect(!model.selection.isSelected(first), "the cleaned target leaves the selection")
        #expect(model.selection.isSelected(second), "the rest of the selection stays intact")
    }
}
