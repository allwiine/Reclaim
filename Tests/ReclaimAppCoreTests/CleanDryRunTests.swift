//
//  CleanDryRunTests.swift
//  ReclaimAppCoreTests
//
//  Orchestration-layer tests against stubbed scan/clean executors —
//  no filesystem, no Trash, deterministic. Split out of CleanTests: a
//  dry run's projections must be honest about what got measured and
//  what actually got credited.
//

import Foundation
import ReclaimKit
import Synchronization
import Testing
@testable import ReclaimAppCore

@MainActor
@Suite("Clean — dry run and freed-space honesty")
struct CleanDryRunTests {
    @Test("A dry run reports projections and touches nothing")
    func dryRunTouchesNothing() async {
        let store = TemporaryDefaults()
        let cache = target("cache")
        let cleanCalls = Mutex(0)
        let model = AppModel(
            targets: [cache],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in
                    measured(100, cleanupPaths: [URL(filePath: "/fixture/a"), URL(filePath: "/fixture/b")])
                },
                clean: { _, _, _ in
                    cleanCalls.withLock { $0 += 1 }
                    return CleanOutcome(removedItems: 1)
                }
            ),
            historyStore: temporaryHistoryStore()
        )
        model.settings.dryRun = true

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.cleaner.cleanSelected()
        await model.cleaner.cleanTask?.value

        #expect(cleanCalls.withLock { $0 } == 0, "a dry run must never reach the engine")
        #expect(model.activity.lastCleanSummary?.isDryRun == true)
        #expect(model.activity.lastCleanSummary?.reclaimedBytes == 100)
        #expect(model.activity.lastCleanSummary?.itemsRemoved == 2)
        #expect(model.selection.isSelected(cache), "the selection survives a dry run")
        #expect(model.results.status(of: "cache").bytes == 100, "measurements stay untouched")
        #expect(model.history.entries.isEmpty, "dry runs are not history")
    }

    @Test("Freed space is not credited when every removal failed")
    func reclaimedNotCreditedWithoutRemoval() async {
        let store = TemporaryDefaults()
        let shrinker = target("shrinker")
        let scanCount = Mutex(0)
        let model = AppModel(
            targets: [shrinker],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in
                    // First call is the initial scan (100). The post-clean
                    // rescan measures less, as if the tool pruned its own
                    // cache between scan and clean.
                    let n = scanCount.withLock { $0 += 1; return $0 }
                    return measured(n == 1 ? 100 : 10)
                },
                clean: { _, _, _ in
                    CleanOutcome(
                        removedItems: 0,
                        failures: [CleanFailure(path: "/locked", message: "locked")]
                    )
                }
            ),
            historyStore: temporaryHistoryStore()
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.selection.setSelected(shrinker, true)
        model.cleaner.cleanSelected()
        await model.cleaner.cleanTask?.value

        let summary = model.activity.lastCleanSummary
        // The rescan saw a 90-byte drop, but no disposal succeeded — so
        // Reclaim must not claim it reclaimed anything.
        #expect(summary?.reclaimedBytes == 0)
        #expect(summary?.cleanedTargets == 0)
        #expect(summary?.failedTargets == 1)
    }

    @Test("Freed space is only claimed when the rescan can measure it")
    func freedSpaceHonesty() async {
        let store = TemporaryDefaults()
        let command = commandTarget("command")
        let broken = target("broken")
        let scanCount = Mutex(0)

        let model = AppModel(
            targets: [command, broken],
            defaults: store.defaults,
            executors: Executors(
                scan: { t in
                    if t.id == "command" { return .unmeasurable }
                    // First scan measures; the post-clean rescan fails.
                    let calls = scanCount.withLock { $0 += 1; return $0 }
                    return calls == 1 ? measured(100) : .failed(message: "denied")
                },
                clean: { _, _, _ in CleanOutcome(removedItems: 1) }
            ),
            historyStore: temporaryHistoryStore()
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.selection.setSelected(command, true)
        model.cleaner.cleanSelected()
        await model.cleaner.cleanTask?.value

        let summary = model.activity.lastCleanSummary
        #expect(summary?.reclaimedBytes == 0, "an unmeasurable result must not be guessed")
        #expect(summary?.cleaned.first?.bytesFreed == nil, "command targets report unknown, not zero")

        let second = AppModel(
            targets: [broken],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in
                    let calls = scanCount.withLock { $0 += 1; return $0 }
                    return calls == 1 ? measured(100) : .failed(message: "denied")
                },
                clean: { _, _, _ in CleanOutcome(removedItems: 1) }
            ),
            historyStore: temporaryHistoryStore()
        )
        scanCount.withLock { $0 = 0 }
        second.scanner.scanAll()
        await second.scanner.scanTask?.value
        second.selection.setSelected(broken, true)
        second.cleaner.cleanSelected()
        await second.cleaner.cleanTask?.value

        #expect(
            second.activity.lastCleanSummary?.reclaimedBytes == 0,
            "a failed rescan must not claim the full size as freed"
        )
        #expect(second.activity.lastCleanSummary?.cleaned.first?.bytesFreed == nil)
    }
}
