//
//  CleanSafetyTests.swift
//  ReclaimAppCoreTests
//
//  Orchestration-layer tests against stubbed scan/clean executors —
//  no filesystem, no Trash, deterministic. Split out of CleanTests:
//  the scan-time safety pins and cooperative stopping of a clean pass.
//

import Foundation
import ReclaimKit
import Synchronization
import Testing
@testable import ReclaimAppCore

@Suite("Clean — safety pins and stopping")
struct CleanSafetyTests {
    @Test("Cleaning refuses a cleanup path whose root was swapped for a symlink after the scan")
    func symlinkSwapAfterScanIsRefused() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "reclaim-pin-\(UUID().uuidString)")
        let realCache = tmp.appending(path: "cache")
        let child = realCache.appending(path: "child")
        let evil = tmp.appending(path: "evil")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: evil, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = TemporaryDefaults()
        let swappable = target("swappable")
        let received = Mutex<[URL]>([])
        let model = AppModel(
            targets: [swappable],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in
                    .measured(
                        DiskMeasurement(bytes: 100, fileCount: 1),
                        resolvedPaths: [realCache],
                        cleanupPaths: [child]
                    )
                },
                clean: { _, paths, _ in
                    received.withLock { $0 = paths }
                    return CleanOutcome(removedItems: paths.count)
                }
            ),
            historyStore: temporaryHistoryStore()
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value

        // Swap the real cache root for a symlink pointing elsewhere,
        // exactly as an attacker would between scan and confirmation.
        try FileManager.default.removeItem(at: realCache)
        try FileManager.default.createSymbolicLink(at: realCache, withDestinationURL: evil)

        model.selection.setSelected(swappable, true)
        model.cleaner.cleanSelected()
        await model.cleaner.cleanTask?.value

        // The child's parent no longer resolves to the scan-time root, so
        // the path is refused: the executor is handed nothing and the
        // summary records a failure.
        #expect(received.withLock { $0 }.isEmpty, "the swapped path must not reach the executor")
        #expect(model.activity.lastCleanSummary?.failures.isEmpty == false)
    }

    @Test("Stopping a clean pass finishes the current target and skips the rest")
    func stoppableCleanPass() async {
        let store = TemporaryDefaults()
        let first = target("first")
        let second = target("second")
        let gate = DispatchSemaphore(value: 0)
        let cleaned = Mutex<[String]>([])

        let model = AppModel(
            targets: [first, second],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) },
                clean: { t, _, _ in
                    if t.id == "first" { gate.wait() }
                    cleaned.withLock { $0.append(t.id) }
                    return CleanOutcome(removedItems: 1)
                }
            ),
            historyStore: temporaryHistoryStore()
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.selection.setSelected(first, true)
        model.selection.setSelected(second, true)
        model.cleaner.cleanSelected()

        // Wait (bounded) until the first job is reported in flight.
        for _ in 0..<10_000 where model.activity.cleanProgress == nil {
            await Task.yield()
        }
        #expect(model.activity.cleanProgress?.targetName == "first")
        #expect(model.activity.cleanProgress?.total == 2)

        model.cleaner.cancelClean()
        gate.signal()
        await model.cleaner.cleanTask?.value

        #expect(cleaned.withLock { $0 } == ["first"], "the in-flight target finishes; the rest are skipped")
        #expect(model.activity.cleanProgress == nil)
        #expect(model.activity.lastCleanSummary?.wasStopped == true)
        #expect(model.selection.isSelected(second), "skipped targets stay selected")
        #expect(model.results.status(of: "second").bytes == 100, "skipped targets keep their measurement")
    }
}
