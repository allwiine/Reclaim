//
//  ProjectCleanScopeTests.swift
//  ReclaimAppCoreTests
//
//  Dev-folder feature orchestration against stubbed executors:
//  project-scoped clean passes. Split out of ProjectCleanTests to
//  stay under the file-length gate.
//

import Foundation
import ReclaimKit
import Synchronization
import Testing
@testable import ReclaimAppCore

@Suite("Projects — scoped cleaning")
struct ProjectCleanScopeTests {
    @Test("A project-scoped clean touches only that project's ticked artifacts")
    func cleanSingleProject() async throws {
        let store = TemporaryDefaults()
        let appModules = artifact("/dev/app/node_modules", bytes: 500)
        let libModules = artifact("/dev/lib/node_modules", bytes: 300)
        let appBefore = project("/dev/app", devRoot: "/dev", artifacts: [appModules])
        let appAfter = project("/dev/app", devRoot: "/dev", artifacts: [])
        let lib = project("/dev/lib", devRoot: "/dev", artifacts: [libModules])
        let scanCount = Mutex(0)
        let cleanedPaths = Mutex<[String]>([])
        let targetCleans = Mutex(0)

        let model = AppModel(
            targets: [target("cache")],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) },
                clean: { _, _, _ in
                    targetCleans.withLock { $0 += 1 }
                    return CleanOutcome(removedItems: 1)
                },
                projectScan: { root in
                    let pass = scanCount.withLock { count in
                        count += 1
                        return count
                    }
                    return DevRootScan(
                        root: root,
                        projects: pass == 1 ? [appBefore, lib] : [appAfter, lib]
                    )
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
        model.projects.setArtifactSelected(appModules, true)
        model.projects.setArtifactSelected(libModules, true)
        // Post-scan auto-selection ticked the safe registry target too.
        #expect(model.selection.ids.contains("cache"))

        model.cleaner.cleanSelected(scope: .projectArtifacts("/dev/app"))
        await model.cleaner.cleanTask?.value

        // Only the app project's artifact was disposed; no registry pass.
        #expect(cleanedPaths.withLock { $0 } == ["/dev/app/node_modules"])
        #expect(targetCleans.withLock { $0 } == 0)
        // The rest of the selection survives.
        #expect(model.selection.ids.contains("cache"))
        #expect(model.projects.isArtifactSelected(libModules))
        #expect(!model.projects.isArtifactSelected(appModules))
        let summary = try #require(model.activity.lastCleanSummary)
        #expect(summary.cleanedArtifacts.map(\.id) == ["/dev/app/node_modules"])
        #expect(summary.reclaimedBytes == 500)
    }

    @Test("A project-scoped dry run projects only that project's artifacts")
    func dryRunSingleProject() async throws {
        let store = TemporaryDefaults()
        let appModules = artifact("/dev/app/node_modules", bytes: 500)
        let libModules = artifact("/dev/lib/node_modules", bytes: 300)
        let app = project("/dev/app", devRoot: "/dev", artifacts: [appModules])
        let lib = project("/dev/lib", devRoot: "/dev", artifacts: [libModules])
        let cleanCalls = Mutex(0)
        let model = AppModel(
            targets: [],
            defaults: store.defaults,
            executors: Executors(
                projectScan: { root in
                    DevRootScan(root: root, projects: [app, lib])
                },
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
        model.projects.setArtifactSelected(appModules, true)
        model.projects.setArtifactSelected(libModules, true)

        model.cleaner.cleanSelected(scope: .projectArtifacts("/dev/app"))

        #expect(cleanCalls.withLock { $0 } == 0)
        let summary = try #require(model.activity.lastCleanSummary)
        #expect(summary.isDryRun)
        #expect(summary.cleanedArtifacts.map(\.id) == ["/dev/app/node_modules"])
        #expect(summary.reclaimedBytes == 500)
        // Dry run leaves the whole selection intact.
        #expect(model.projects.isArtifactSelected(appModules))
        #expect(model.projects.isArtifactSelected(libModules))
    }

    @Test("A project-scoped clean with an unknown id is a no-op")
    func cleanUnknownProjectIsNoOp() async {
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
        model.projects.addDevRoot(URL(filePath: "/dev"))
        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.projects.setArtifactSelected(nodeModules, true)

        model.cleaner.cleanSelected(scope: .projectArtifacts("/dev/gone"))
        await model.cleaner.cleanTask?.value

        #expect(cleanCalls.withLock { $0 } == 0)
        #expect(model.activity.lastCleanSummary == nil)
        #expect(model.projects.isArtifactSelected(nodeModules))
    }
}
