//
//  ProjectCleanTests.swift
//  ReclaimAppCoreTests
//
//  Dev-folder feature orchestration against stubbed executors:
//  artifact cleaning, dry runs, and rescans.
//

import Foundation
import ReclaimKit
import Synchronization
import Testing
@testable import ReclaimAppCore

@Suite("Projects — cleaning artifacts")
struct ProjectCleanTests {
    @Test("Cleaning selected artifacts disposes, verifies, and rescans")
    func cleanArtifacts() async throws {
        let store = TemporaryDefaults()
        let nodeModules = artifact("/dev/app/node_modules", bytes: 500)
        let before = project("/dev/app", devRoot: "/dev", artifacts: [nodeModules])
        let after = project("/dev/app", devRoot: "/dev", artifacts: [])
        let scanCount = Mutex(0)
        let cleanedPaths = Mutex<[String]>([])

        let model = AppModel(
            targets: [],
            defaults: store.defaults,
            executors: Executors(
                projectScan: { root in
                    let pass = scanCount.withLock { count in
                        count += 1
                        return count
                    }
                    return DevRootScan(root: root, projects: pass == 1 ? [before] : [after])
                },
                artifactClean: { paths, _ in
                    cleanedPaths.withLock { $0.append(contentsOf: paths.map(\.path)) }
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

        // The engine saw exactly the scan-time snapshot path.
        #expect(cleanedPaths.withLock { $0 } == ["/dev/app/node_modules"])
        // The fixture path does not exist on disk, so removal verifies.
        let summary = try #require(model.activity.lastCleanSummary)
        #expect(summary.cleanedArtifacts.count == 1)
        #expect(summary.cleanedArtifacts.first?.bytesFreed == 500)
        #expect(summary.reclaimedBytes == 500)
        #expect(summary.itemsRemoved == 1)
        // The affected root was re-discovered (executor ran twice).
        #expect(scanCount.withLock { $0 } == 2)
        #expect(model.projects.discovered.first?.artifacts.isEmpty == true)
        // Selection cleared; history recorded the artifact.
        #expect(model.projects.artifactSelection.isEmpty)
        #expect(model.history.entries.first?.items?.contains {
            $0.targetID == "artifact:/dev/app/node_modules"
        } == true)
    }

    @Test("A dry run projects artifact bytes without touching anything")
    func dryRunArtifacts() async throws {
        let store = TemporaryDefaults()
        let nodeModules = artifact("/dev/app/node_modules", bytes: 500)
        let fixture = project("/dev/app", devRoot: "/dev", artifacts: [nodeModules])
        let cleanCalls = Mutex(0)
        let model = AppModel(
            targets: [],
            defaults: store.defaults,
            executors: Executors(
                projectScan: { root in DevRootScan(root: root, projects: [fixture]) },
                artifactClean: { paths, _ in
                    cleanCalls.withLock { $0 += 1 }
                    return CleanOutcome(removedItems: paths.count)
                }
            ),
            historyStore: temporaryHistoryStore()
        )
        model.settings.dryRun = true
        model.projects.addDevRoot(URL(filePath: "/dev"))
        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.projects.setArtifactSelected(nodeModules, true)

        model.cleaner.cleanSelected()

        #expect(cleanCalls.withLock { $0 } == 0)
        let summary = try #require(model.activity.lastCleanSummary)
        #expect(summary.isDryRun)
        #expect(summary.cleanedArtifacts.first?.bytesFreed == 500)
        #expect(summary.reclaimedBytes == 500)
        // Dry run leaves the selection intact.
        #expect(model.projects.isArtifactSelected(nodeModules))
    }

    @Test("Clean-just-this passes never touch artifacts")
    func limitedCleanExcludesArtifacts() async {
        let store = TemporaryDefaults()
        let nodeModules = artifact("/dev/app/node_modules", bytes: 500)
        let fixture = project("/dev/app", devRoot: "/dev", artifacts: [nodeModules])
        let cleanCalls = Mutex(0)
        let model = AppModel(
            targets: [target("cache")],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) },
                clean: { _, _, _ in CleanOutcome(removedItems: 1) },
                projectScan: { root in DevRootScan(root: root, projects: [fixture]) },
                artifactClean: { paths, _ in
                    cleanCalls.withLock { $0 += 1 }
                    return CleanOutcome(removedItems: paths.count)
                }
            ),
            historyStore: temporaryHistoryStore()
        )
        model.projects.addDevRoot(URL(filePath: "/dev"))
        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.projects.setArtifactSelected(nodeModules, true)

        model.cleaner.cleanSelected(scope: .targets(["cache"]))
        await model.cleaner.cleanTask?.value

        #expect(cleanCalls.withLock { $0 } == 0)
        #expect(model.projects.isArtifactSelected(nodeModules))  // selection survives
    }
}
