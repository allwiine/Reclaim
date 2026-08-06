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
            }
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
            }
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
            }
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
