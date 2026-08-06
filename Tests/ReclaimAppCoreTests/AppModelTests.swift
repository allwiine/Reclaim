//
//  AppModelTests.swift
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

// MARK: - Fixtures

private func target(
    _ id: String,
    safety: SafetyLevel = .safe,
    strategy: CleanupStrategy = .removeContents
) -> CleanupTarget {
    CleanupTarget(
        id: id,
        name: id,
        summary: "Fixture",
        category: .otherTools,
        safety: safety,
        pathPatterns: ["~/\(id)"],
        strategy: strategy
    )
}

private func commandTarget(_ id: String) -> CleanupTarget {
    CleanupTarget(
        id: id,
        name: id,
        summary: "Fixture",
        category: .otherTools,
        safety: .safe,
        pathPatterns: [],
        strategy: .command(CommandSpec(
            executablePath: "/usr/bin/true", arguments: [], displayCommand: "true"
        ))
    )
}

private func measured(
    _ bytes: Int64, cleanupPaths: [URL] = [URL(filePath: "/fixture/a")]
) -> TargetStatus {
    .measured(
        DiskMeasurement(bytes: bytes, fileCount: 1),
        resolvedPaths: [URL(filePath: "/fixture")],
        cleanupPaths: cleanupPaths
    )
}

/// History store pointed at a throwaway file so tests never touch the
/// real Application Support state.
private func temporaryHistoryStore() -> CleanHistoryStore {
    CleanHistoryStore(fileURL: FileManager.default.temporaryDirectory
        .appending(path: "reclaim-history-\(UUID().uuidString).json"))
}

/// UserDefaults suite that cleans up after itself.
private final class TemporaryDefaults {
    let name = "AppModelTests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
    }
}

// MARK: - Tests

@MainActor
@Suite("App model")
struct AppModelTests {
    @Test("Scanning populates statuses and records the scan")
    func scanLifecycle() async {
        let store = TemporaryDefaults()
        let model = AppModel(
            targets: [target("cache"), target("missing")],
            defaults: store.defaults,
            scanExecutor: { t in t.id == "cache" ? measured(100) : .notInstalled }
        )

        model.scanAll()
        #expect(model.isScanning)
        await model.scanTask?.value

        #expect(model.isScanning == false)
        #expect(model.lastScan != nil)
        #expect(model.status(of: "cache").bytes == 100)
        #expect(model.status(of: "missing") == .notInstalled)
        #expect(model.totalFoundBytes == 100)
    }

    @Test("A completed scan is marked complete")
    func completedScanIsComplete() async {
        let store = TemporaryDefaults()
        let model = AppModel(
            targets: [target("cache")],
            defaults: store.defaults,
            scanExecutor: { _ in measured(100) }
        )

        model.scanAll()
        await model.scanTask?.value

        #expect(model.lastScanWasComplete)
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
            scanExecutor: { t in
                guard t.id == "slow" else { return measured(100) }
                // Block until the test has cancelled, then behave like
                // the real scanner does on cancellation.
                gate.wait()
                return Task.isCancelled ? .idle : measured(100)
            }
        )

        model.scanAll()
        model.cancelScan()
        gate.signal()
        await model.scanTask?.value

        #expect(model.lastScan != nil, "partial data is real data — the scan still happened")
        #expect(model.status(of: "fast").bytes == 100, "completed measurements survive")
        #expect(!model.lastScanWasComplete, "a stopped scan must not present itself as complete")
    }

    @Test("The Full Disk Access verdict is refreshed when scanning")
    func fullDiskAccessVerdict() async {
        let store = TemporaryDefaults()
        let model = AppModel(
            targets: [target("cache")],
            defaults: store.defaults,
            scanExecutor: { _ in measured(100) },
            fullDiskAccessProbe: { false }
        )
        #expect(model.hasFullDiskAccess == nil, "no verdict before the first scan")

        model.scanAll()
        await model.scanTask?.value

        #expect(model.hasFullDiskAccess == false)
    }

    @Test("Only measured non-empty cleanable targets are selectable")
    func selectionRules() async {
        let store = TemporaryDefaults()
        let manual = target("manual", strategy: .manual(instructions: "Use the tool."))
        let empty = target("empty")
        let full = target("full")
        let command = commandTarget("command")
        let model = AppModel(
            targets: [manual, empty, full, command],
            defaults: store.defaults,
            scanExecutor: { t in
                switch t.id {
                case "manual": measured(500)
                case "empty": measured(0)
                case "full": measured(100)
                default: .unmeasurable
                }
            }
        )

        model.scanAll()
        await model.scanTask?.value

        #expect(!model.isSelectable(manual), "manual targets must never be selectable")
        #expect(!model.isSelectable(empty), "empty targets have nothing to clean")
        #expect(model.isSelectable(full))
        #expect(model.isSelectable(command), "command targets are cleanable while unmeasured")

        model.setSelected(command, true)
        model.setSelected(full, true)
        #expect(
            model.selectedTargets.map(\.id) == ["full", "command"],
            "selected targets come back in registry order"
        )
    }

    @Test("selectAllSafe skips caution-rated targets")
    func selectAllSafeRespectsSafety() async {
        let store = TemporaryDefaults()
        let safe = target("safe", safety: .safe)
        let risky = target("risky", safety: .caution)
        let model = AppModel(
            targets: [safe, risky],
            defaults: store.defaults,
            scanExecutor: { _ in measured(100) }
        )

        model.scanAll()
        await model.scanTask?.value
        model.selectAllSafe()

        #expect(model.isSelected(safe))
        #expect(!model.isSelected(risky))
    }

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
            scanExecutor: { _ in
                // First scan sees 100 bytes; the post-clean rescan sees 0.
                let calls = scanCount.withLock { $0 += 1; return $0 }
                return calls == 1 ? measured(100, cleanupPaths: cleanupPaths) : measured(0)
            },
            cleanExecutor: { t, paths, disposal in
                cleaned.withLock { $0.append((t.id, paths, disposal)) }
                return CleanOutcome(removedItems: paths.count)
            },
            historyStore: temporaryHistoryStore()
        )

        model.scanAll()
        await model.scanTask?.value
        model.setSelected(cache, true)
        model.cleanSelected()
        await model.cleanTask?.value

        let calls = cleaned.withLock { $0 }
        #expect(calls.count == 1)
        #expect(calls.first?.1 == cleanupPaths)
        #expect(calls.first?.2 == .trash)
        #expect(model.isCleaning == false)
        #expect(model.selection.isEmpty)
        #expect(model.lastCleanSummary?.reclaimedBytes == 100)
        #expect(model.status(of: "cache").bytes == 0, "post-clean rescan must be reflected")
    }

    @Test("Summary counts only targets that actually had removals")
    func summaryAccuracy() async {
        let store = TemporaryDefaults()
        let ok = target("ok")
        let broken = target("broken")

        let model = AppModel(
            targets: [ok, broken],
            defaults: store.defaults,
            scanExecutor: { _ in measured(100) },
            cleanExecutor: { t, _, _ in
                t.id == "ok"
                    ? CleanOutcome(removedItems: 2)
                    : CleanOutcome(
                        removedItems: 0,
                        failures: [CleanFailure(path: "/x", message: "locked")]
                    )
            },
            historyStore: temporaryHistoryStore()
        )

        model.scanAll()
        await model.scanTask?.value
        model.setSelected(ok, true)
        model.setSelected(broken, true)
        model.cleanSelected()
        await model.cleanTask?.value

        let summary = model.lastCleanSummary
        #expect(summary?.itemsRemoved == 2)
        #expect(summary?.cleanedTargets == 1, "a target with zero removals was not cleaned")
        #expect(summary?.failedTargets == 1)
        #expect(summary?.failures.count == 1)
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
            scanExecutor: { _ in measured(100) },
            cleanExecutor: { t, _, _ in
                if t.id == "first" { gate.wait() }
                cleaned.withLock { $0.append(t.id) }
                return CleanOutcome(removedItems: 1)
            },
            historyStore: temporaryHistoryStore()
        )

        model.scanAll()
        await model.scanTask?.value
        model.setSelected(first, true)
        model.setSelected(second, true)
        model.cleanSelected()

        // Wait (bounded) until the first job is reported in flight.
        for _ in 0..<10_000 where model.cleanProgress == nil {
            await Task.yield()
        }
        #expect(model.cleanProgress?.targetName == "first")
        #expect(model.cleanProgress?.total == 2)

        model.cancelClean()
        gate.signal()
        await model.cleanTask?.value

        #expect(cleaned.withLock { $0 } == ["first"], "the in-flight target finishes; the rest are skipped")
        #expect(model.cleanProgress == nil)
        #expect(model.lastCleanSummary?.wasStopped == true)
        #expect(model.isSelected(second), "skipped targets stay selected")
        #expect(model.status(of: "second").bytes == 100, "skipped targets keep their measurement")
    }

    @Test("A finished scan preselects Safe items, honoring the Caution setting")
    func postScanPreselection() async {
        let store = TemporaryDefaults()
        let safe = target("safe", safety: .safe)
        let risky = target("risky", safety: .caution)
        let manual = target("manual", strategy: .manual(instructions: "Use the tool."))
        let model = AppModel(
            targets: [safe, risky, manual],
            defaults: store.defaults,
            scanExecutor: { _ in measured(100) },
            historyStore: temporaryHistoryStore()
        )

        model.scanAll()
        await model.scanTask?.value

        #expect(model.isSelected(safe), "Safe items come ticked after a scan")
        #expect(!model.isSelected(risky), "Caution items stay unticked by default")
        #expect(!model.isSelected(manual), "manual targets can never be selected")

        model.preselectCaution = true
        model.scanAll()
        await model.scanTask?.value

        #expect(model.isSelected(risky), "the Caution preselection setting is honored")
    }

    @Test("A dry run reports projections and touches nothing")
    func dryRunTouchesNothing() async {
        let store = TemporaryDefaults()
        let cache = target("cache")
        let cleanCalls = Mutex(0)
        let model = AppModel(
            targets: [cache],
            defaults: store.defaults,
            scanExecutor: { _ in
                measured(100, cleanupPaths: [URL(filePath: "/fixture/a"), URL(filePath: "/fixture/b")])
            },
            cleanExecutor: { _, _, _ in
                cleanCalls.withLock { $0 += 1 }
                return CleanOutcome(removedItems: 1)
            },
            historyStore: temporaryHistoryStore()
        )
        model.dryRun = true

        model.scanAll()
        await model.scanTask?.value
        model.cleanSelected()
        await model.cleanTask?.value

        #expect(cleanCalls.withLock { $0 } == 0, "a dry run must never reach the engine")
        #expect(model.lastCleanSummary?.isDryRun == true)
        #expect(model.lastCleanSummary?.reclaimedBytes == 100)
        #expect(model.lastCleanSummary?.itemsRemoved == 2)
        #expect(model.isSelected(cache), "the selection survives a dry run")
        #expect(model.status(of: "cache").bytes == 100, "measurements stay untouched")
        #expect(model.history.isEmpty, "dry runs are not history")
    }

    @Test("A real clean pass is recorded in persistent history")
    func historyRecording() async {
        let store = TemporaryDefaults()
        let historyStore = temporaryHistoryStore()
        let cache = target("cache")
        let scanCount = Mutex(0)
        let model = AppModel(
            targets: [cache],
            defaults: store.defaults,
            scanExecutor: { _ in
                let calls = scanCount.withLock { $0 += 1; return $0 }
                return calls == 1 ? measured(100) : measured(0)
            },
            cleanExecutor: { _, _, _ in CleanOutcome(removedItems: 3) },
            historyStore: historyStore
        )

        model.scanAll()
        await model.scanTask?.value
        model.cleanSelected()
        await model.cleanTask?.value

        #expect(model.history.count == 1)
        #expect(model.history.first?.targetNames == ["cache"])
        #expect(model.history.first?.itemsRemoved == 3)
        #expect(model.history.first?.reclaimedBytes == 100)
        #expect(model.reclaimedAllTimeBytes == 100)
        #expect(model.lastCleanSummary?.cleaned.map(\.name) == ["cache"])

        // The entry must survive a fresh model (i.e. an app restart).
        for _ in 0..<10_000 where historyStore.load().isEmpty {
            await Task.yield()
        }
        #expect(historyStore.load().count == 1)
    }

    @Test("Scan progress is live during the pass and gone afterwards")
    func scanProgressLifecycle() async {
        let store = TemporaryDefaults()
        let model = AppModel(
            targets: [target("a"), target("b")],
            defaults: store.defaults,
            scanExecutor: { _ in measured(100) },
            historyStore: temporaryHistoryStore()
        )
        #expect(model.scanProgress == nil)

        model.scanAll()
        #expect(model.scanProgress?.total == 2)

        await model.scanTask?.value
        #expect(model.scanProgress == nil)
    }

    @Test("The weekly background scan fires only when due")
    func backgroundScanScheduling() async {
        let store = TemporaryDefaults()
        let model = AppModel(
            targets: [target("cache")],
            defaults: store.defaults,
            scanExecutor: { _ in measured(100) },
            historyStore: temporaryHistoryStore()
        )

        #expect(model.nextBackgroundScanDate == nil, "no schedule before the first scan")
        model.runBackgroundScanIfDue()
        #expect(model.scanTask == nil, "never scans without a previous scan on record")

        model.scanAll()
        await model.scanTask?.value
        let next = model.nextBackgroundScanDate
        #expect(next != nil)

        model.runBackgroundScanIfDue(now: .now)
        #expect(!model.isScanning, "not due yet — a scan just finished")

        model.runBackgroundScanIfDue(now: next!.addingTimeInterval(60))
        #expect(model.isScanning, "a week later the scan starts")
        await model.scanTask?.value

        model.weeklyScanEnabled = false
        #expect(model.nextBackgroundScanDate == nil, "disabling removes the schedule")
    }

    @Test("Breakdowns load once per target and clear on rescan")
    func breakdownLifecycle() async {
        let store = TemporaryDefaults()
        let cache = target("cache")
        let computeCalls = Mutex(0)
        let model = AppModel(
            targets: [cache],
            defaults: store.defaults,
            scanExecutor: { _ in measured(100) },
            breakdownExecutor: { _ in
                computeCalls.withLock { $0 += 1 }
                return [BreakdownEntry(name: "big", bytes: 80)]
            },
            historyStore: temporaryHistoryStore()
        )

        model.loadBreakdown(for: cache)
        #expect(model.breakdowns["cache"] == nil, "nothing to break down before a scan")

        model.scanAll()
        await model.scanTask?.value
        model.loadBreakdown(for: cache)
        for _ in 0..<10_000 where model.breakdowns["cache"] == nil {
            await Task.yield()
        }
        #expect(model.breakdowns["cache"]?.first?.name == "big")

        model.loadBreakdown(for: cache)
        #expect(computeCalls.withLock { $0 } == 1, "cached breakdowns are not recomputed")

        model.scanAll()
        #expect(model.breakdowns.isEmpty, "a new scan invalidates every breakdown")
        await model.scanTask?.value
    }

    @Test("The disposal chosen in Settings reaches the clean executor")
    func disposalSnapshot() async {
        let store = TemporaryDefaults()
        let cache = target("cache")
        let usedDisposal = Mutex<Disposal?>(nil)

        let model = AppModel(
            targets: [cache],
            defaults: store.defaults,
            scanExecutor: { _ in measured(100) },
            cleanExecutor: { _, _, disposal in
                usedDisposal.withLock { $0 = disposal }
                return CleanOutcome(removedItems: 1)
            },
            historyStore: temporaryHistoryStore()
        )
        model.disposal = .delete

        model.scanAll()
        await model.scanTask?.value
        model.setSelected(cache, true)
        model.cleanSelected()
        await model.cleanTask?.value

        #expect(usedDisposal.withLock { $0 } == .delete)
    }
}
