//
//  ScanTests.swift
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

@Suite("Scan")
struct ScanTests {
    @Test("Scanning populates statuses and records the scan")
    func scanLifecycle() async {
        let store = TemporaryDefaults()
        let model = AppModel(
            targets: [target("cache"), target("missing")],
            defaults: store.defaults,
            executors: Executors(
                scan: { t in t.id == "cache" ? measured(100) : .notInstalled }
            )
        )

        model.scanner.scanAll()
        #expect(model.activity.isScanning)
        await model.scanner.scanTask?.value

        #expect(model.activity.isScanning == false)
        #expect(model.results.lastScan != nil)
        #expect(model.results.status(of: "cache").bytes == 100)
        #expect(model.results.status(of: "missing") == .notInstalled)
        #expect(model.totalFoundBytes == 100)
    }

    @Test("A completed scan is marked complete")
    func completedScanIsComplete() async {
        let store = TemporaryDefaults()
        let model = AppModel(
            targets: [target("cache")],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) }
            )
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value

        #expect(model.results.lastScanWasComplete)
    }

    @Test("A cancelled scan keeps partial results but is marked incomplete")
    func cancelledScanIsPartial() async {
        let store = TemporaryDefaults()
        let gate = DispatchSemaphore(value: 0)
        let fast = target("fast")
        let slow = target("slow")
        let model = AppModel(
            targets: [fast, slow],
            defaults: store.defaults,
            executors: Executors(
                scan: { t in
                    guard t.id == "slow" else { return measured(100) }
                    // Block until the test has cancelled, then behave like
                    // the real scanner does on cancellation.
                    gate.wait()
                    return Task.isCancelled ? .idle : measured(100)
                }
            )
        )

        model.scanner.scanAll()
        model.scanner.cancelScan()
        gate.signal()
        await model.scanner.scanTask?.value

        #expect(model.results.lastScan != nil, "partial data is real data — the scan still happened")
        #expect(model.results.status(of: "fast").bytes == 100, "completed measurements survive")
        #expect(!model.results.lastScanWasComplete, "a stopped scan must not present itself as complete")
    }

    @Test("Scan progress is live during the pass and gone afterwards")
    func scanProgressLifecycle() async {
        let store = TemporaryDefaults()
        let model = AppModel(
            targets: [target("a"), target("b")],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) }
            ),
            historyStore: temporaryHistoryStore()
        )
        #expect(model.activity.scanProgress == nil)

        model.scanner.scanAll()
        #expect(model.activity.scanProgress?.total == 2)

        await model.scanner.scanTask?.value
        #expect(model.activity.scanProgress == nil)
    }

    @Test("The weekly background scan fires only when due")
    func backgroundScanScheduling() async {
        let store = TemporaryDefaults()
        let model = AppModel(
            targets: [target("cache")],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) }
            ),
            historyStore: temporaryHistoryStore()
        )

        #expect(model.scanner.nextBackgroundScanDate == nil, "no schedule before the first scan")
        model.scanner.runBackgroundScanIfDue()
        #expect(model.scanner.scanTask == nil, "never scans without a previous scan on record")

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        let next = model.scanner.nextBackgroundScanDate
        #expect(next != nil)

        model.scanner.runBackgroundScanIfDue(now: .now)
        #expect(!model.activity.isScanning, "not due yet — a scan just finished")

        model.scanner.runBackgroundScanIfDue(now: next!.addingTimeInterval(60))
        #expect(model.activity.isScanning, "a week later the scan starts")
        await model.scanner.scanTask?.value

        model.settings.weeklyScanEnabled = false
        #expect(model.scanner.nextBackgroundScanDate == nil, "disabling removes the schedule")
    }

    @Test("The background scan defers while a confirmation is open")
    func backgroundScanDefersWhileReviewing() async {
        let store = TemporaryDefaults()
        let model = AppModel(
            targets: [target("cache")],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) }
            ),
            historyStore: temporaryHistoryStore()
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        let overdue = model.scanner.nextBackgroundScanDate!.addingTimeInterval(60)

        model.activity.isReviewingSelection = true
        model.scanner.runBackgroundScanIfDue(now: overdue)
        #expect(!model.activity.isScanning, "a background scan must never clear a selection under review")

        model.activity.isReviewingSelection = false
        model.scanner.runBackgroundScanIfDue(now: overdue)
        #expect(model.activity.isScanning)
        await model.scanner.scanTask?.value
    }

    @Test("Cancellation state is visible while a scan unwinds")
    func cancellingScanState() async {
        let store = TemporaryDefaults()
        let gate = DispatchSemaphore(value: 0)
        let model = AppModel(
            targets: [target("slow")],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in
                    gate.wait()
                    return .idle
                }
            ),
            historyStore: temporaryHistoryStore()
        )
        #expect(!model.activity.isCancellingScan)

        model.scanner.scanAll()
        model.scanner.cancelScan()
        #expect(model.activity.isCancellingScan, "the Stop button needs to show 'Stopping…'")

        gate.signal()
        await model.scanner.scanTask?.value
        #expect(!model.activity.isCancellingScan, "the flag resets once the pass unwinds")
    }
}
