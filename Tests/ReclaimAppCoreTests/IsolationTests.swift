//
//  IsolationTests.swift
//  ReclaimAppCoreTests
//
//  Pinning tests: proof that every injectable Executors member already
//  runs off the main thread, captured before any concurrency-model
//  change. A ThreadRecorder marks where each stubbed closure actually
//  executed; every assertion below must already hold today. If one
//  ever finds main-thread execution, that is a pre-existing bug to
//  surface, not to relax.
//

import Foundation
import ReclaimKit
import Synchronization
import Testing
@testable import ReclaimAppCore

/// Thread-safe capture of where executor closures actually ran.
nonisolated final class ThreadRecorder: Sendable {
    private let hits = Mutex<[Bool]>([])
    func record() { hits.withLock { $0.append(Thread.isMainThread) } }
    var sawMainThread: Bool { hits.withLock { $0.contains(true) } }
    var count: Int { hits.withLock { $0.count } }
}

@Suite("Isolation")
struct IsolationTests {
    @Test("Scan, project-scan, full-disk-access, and volume executors run off the main thread")
    func scanPathsRunOffMain() async throws {
        let recorder = ThreadRecorder()
        let store = TemporaryDefaults()
        let model = AppModel(
            targets: [target("cache")],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in
                    recorder.record()
                    return measured(100)
                },
                projectScan: { root in
                    recorder.record()
                    return DevRootScan(root: root, projects: [])
                },
                fullDiskAccess: {
                    recorder.record()
                    return true
                },
                volume: {
                    recorder.record()
                    return nil
                }
            ),
            historyStore: temporaryHistoryStore()
        )
        model.projects.addDevRoot(URL(filePath: "/dev"))

        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        // The post-scan volume refresh is an unstructured Task fired
        // from ScanCoordinator.scanAll (see TargetResultsModel
        // .refreshVolumeSpace), so give it a moment to land — same
        // reasoning as the breakdown poll below.
        for _ in 0..<10_000 where recorder.count < 4 {
            await Task.yield()
        }

        #expect(recorder.count >= 4, "every stubbed path was hit")
        #expect(!recorder.sawMainThread)
    }

    @Test("Clean and rescan executors run off the main thread")
    func cleanPathsRunOffMain() async throws {
        let recorder = ThreadRecorder()
        let store = TemporaryDefaults()
        let cache = target("cache")
        let model = AppModel(
            targets: [cache],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in
                    recorder.record()
                    return measured(100)
                },
                clean: { _, paths, _ in
                    recorder.record()
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

        #expect(recorder.count >= 3, "initial scan, clean, and rescan each recorded")
        #expect(!recorder.sawMainThread)
    }

    @Test("Artifact-clean executor runs off the main thread")
    func artifactCleanRunsOffMain() async throws {
        let recorder = ThreadRecorder()
        let store = TemporaryDefaults()
        let nodeModules = artifact("/dev/app/node_modules", bytes: 500)
        let before = project("/dev/app", devRoot: "/dev", artifacts: [nodeModules])
        let after = project("/dev/app", devRoot: "/dev", artifacts: [])
        let scanCount = Mutex(0)
        let model = AppModel(
            targets: [],
            defaults: store.defaults,
            executors: Executors(
                projectScan: { root in
                    recorder.record()
                    let pass = scanCount.withLock { count in
                        count += 1
                        return count
                    }
                    return DevRootScan(root: root, projects: pass == 1 ? [before] : [after])
                },
                artifactClean: { paths, _ in
                    recorder.record()
                    return CleanOutcome(removedItems: paths.count)
                }
            ),
            historyStore: temporaryHistoryStore()
        )
        model.projects.addDevRoot(URL(filePath: "/dev"))
        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.projects.setArtifactSelected(nodeModules, true)

        model.cleaner.cleanSelected()
        await model.cleaner.cleanTask?.value

        #expect(recorder.count >= 3, "initial discovery, artifact clean, and re-discovery each recorded")
        #expect(!recorder.sawMainThread)
    }

    @Test("Breakdown executor runs off the main thread")
    func breakdownRunsOffMain() async throws {
        let recorder = ThreadRecorder()
        let store = TemporaryDefaults()
        let cache = target("cache")
        let model = AppModel(
            targets: [cache],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) },
                breakdown: { _ in
                    recorder.record()
                    return [BreakdownEntry(name: "big", bytes: 80)]
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

        #expect(recorder.count >= 1)
        #expect(!recorder.sawMainThread)
    }
}
