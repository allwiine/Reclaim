//
//  BreakdownTests.swift
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
@Suite("Breakdowns")
struct BreakdownTests {
    @Test("Breakdowns load once per target and clear on rescan")
    func breakdownLifecycle() async {
        let store = TemporaryDefaults()
        let cache = target("cache")
        let computeCalls = Mutex(0)
        let model = AppModel(
            targets: [cache],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) },
                breakdown: { _ in
                    computeCalls.withLock { $0 += 1 }
                    return [BreakdownEntry(name: "big", bytes: 80)]
                }
            ),
            historyStore: temporaryHistoryStore()
        )

        model.breakdowns.load(for: cache)
        #expect(model.breakdowns.entries["cache"] == nil, "nothing to break down before a scan")

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.breakdowns.load(for: cache)
        for _ in 0..<10_000 where model.breakdowns.entries["cache"] == nil {
            await Task.yield()
        }
        #expect(model.breakdowns.entries["cache"]?.first?.name == "big")

        model.breakdowns.load(for: cache)
        #expect(computeCalls.withLock { $0 } == 1, "cached breakdowns are not recomputed")

        model.scanner.scanAll()
        #expect(model.breakdowns.entries.isEmpty, "a new scan invalidates every breakdown")
        await model.scanner.scanTask?.value
    }
}
