//
//  ProjectSelectionTests.swift
//  ReclaimAppCoreTests
//
//  Dev-folder feature orchestration against stubbed executors:
//  artifact and project-level ticking.
//

import Foundation
import ReclaimKit
import Synchronization
import Testing
@testable import ReclaimAppCore

@MainActor
@Suite("Projects — artifact selection")
struct ProjectSelectionTests {
    @Test("Artifact selection follows the selectability rules")
    func artifactSelection() async {
        let store = TemporaryDefaults()
        let full = artifact("/dev/app/node_modules", bytes: 500)
        let empty = artifact("/dev/app/.venv", bytes: 0)
        let fixture = project("/dev/app", devRoot: "/dev", artifacts: [full, empty])
        let model = AppModel(
            targets: [],
            defaults: store.defaults,
            executors: Executors(
                projectScan: { root in DevRootScan(root: root, projects: [fixture]) }
            )
        )
        model.projects.addDevRoot(URL(filePath: "/dev"))
        model.scanner.scanAll()
        await model.scanner.scanTask?.value

        // Artifacts are never auto-selected after a scan.
        #expect(model.projects.artifactSelection.isEmpty)

        #expect(model.projects.isArtifactSelectable(full))
        #expect(!model.projects.isArtifactSelectable(empty))    // nothing to free

        model.projects.setArtifactSelected(full, true)
        #expect(model.projects.isArtifactSelected(full))
        #expect(model.projects.selectedArtifactBytes == 500)
        #expect(model.hasCleanableSelection)

        model.projects.setArtifactSelected(empty, true)          // refused
        #expect(!model.projects.isArtifactSelected(empty))

        model.projects.setArtifactSelected(full, false)
        #expect(!model.hasCleanableSelection)
    }

    @Test("Project-level selection is tri-state over its artifacts")
    func projectTriStateSelection() async throws {
        let store = TemporaryDefaults()
        let nodeModules = artifact("/dev/app/node_modules", bytes: 500)
        let build = artifact("/dev/app/.build", bytes: 300)
        let empty = artifact("/dev/app/.venv", bytes: 0)
        let fixture = project(
            "/dev/app", devRoot: "/dev", artifacts: [nodeModules, build, empty]
        )
        let model = AppModel(
            targets: [],
            defaults: store.defaults,
            executors: Executors(
                projectScan: { root in DevRootScan(root: root, projects: [fixture]) }
            )
        )
        model.projects.addDevRoot(URL(filePath: "/dev"))
        model.scanner.scanAll()
        await model.scanner.scanTask?.value

        #expect(model.projects.isProjectSelectable(fixture))
        #expect(!model.projects.isProjectSelected(fixture))
        #expect(!model.projects.isProjectPartiallySelected(fixture))
        #expect(model.projects.partialSelectionCounts(of: fixture) == nil)

        model.projects.setArtifactSelected(nodeModules, true)
        #expect(!model.projects.isProjectSelected(fixture))
        #expect(model.projects.isProjectPartiallySelected(fixture))
        let counts = try #require(model.projects.partialSelectionCounts(of: fixture))
        #expect(counts.selected == 1)
        #expect(counts.total == 2)          // the empty artifact never counts
        #expect(model.projects.selectedArtifactBytes(of: fixture) == 500)

        model.projects.setProjectSelected(fixture, true)
        #expect(model.projects.isProjectSelected(fixture))
        #expect(!model.projects.isProjectPartiallySelected(fixture))
        // Full selection is not "partial": counts are nil, like targets.
        #expect(model.projects.partialSelectionCounts(of: fixture) == nil)
        // The empty artifact stays unticked (nothing to free).
        #expect(!model.projects.isArtifactSelected(empty))
        #expect(model.projects.selectedArtifactBytes(of: fixture) == 800)
        #expect(model.projects.selectedArtifacts(of: fixture).map(\.id) ==
            ["/dev/app/node_modules", "/dev/app/.build"])

        model.projects.setProjectSelected(fixture, false)
        #expect(model.projects.artifactSelection.isEmpty)
    }

    @Test("An artifact-free project is never selectable")
    func artifactFreeProjectUnselectable() async {
        let store = TemporaryDefaults()
        let bare = project("/dev/bare", devRoot: "/dev", artifacts: [])
        let onlyEmpty = project(
            "/dev/hollow", devRoot: "/dev",
            artifacts: [artifact("/dev/hollow/.venv", bytes: 0)]
        )
        let model = AppModel(
            targets: [],
            defaults: store.defaults,
            executors: Executors(
                projectScan: { root in
                    DevRootScan(root: root, projects: [bare, onlyEmpty])
                }
            )
        )
        model.projects.addDevRoot(URL(filePath: "/dev"))
        model.scanner.scanAll()
        await model.scanner.scanTask?.value

        #expect(!model.projects.isProjectSelectable(bare))
        #expect(!model.projects.isProjectSelectable(onlyEmpty))
        model.projects.setProjectSelected(onlyEmpty, true)       // refused per artifact
        #expect(model.projects.artifactSelection.isEmpty)
        #expect(model.projects.selectableArtifactCount == 0)
    }

    @Test("Select all and clear cover every project's artifacts, never targets")
    func selectAllAndClearArtifacts() async {
        let store = TemporaryDefaults()
        let app = project(
            "/dev/app", devRoot: "/dev",
            artifacts: [artifact("/dev/app/node_modules", bytes: 500)]
        )
        let lib = project(
            "/dev/lib", devRoot: "/dev",
            artifacts: [
                artifact("/dev/lib/.build", bytes: 300),
                artifact("/dev/lib/.venv", bytes: 0),
            ]
        )
        let model = AppModel(
            targets: [target("cache")],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) },
                projectScan: { root in
                    DevRootScan(root: root, projects: [app, lib])
                }
            )
        )
        model.projects.addDevRoot(URL(filePath: "/dev"))
        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        // Post-scan auto-selection ticked the safe registry target.
        #expect(model.selection.ids.contains("cache"))

        model.projects.selectAllArtifacts()
        #expect(model.projects.selectedArtifacts.map(\.id).sorted() ==
            ["/dev/app/node_modules", "/dev/lib/.build"])
        #expect(model.projects.selectableArtifactCount == 2)

        model.projects.clearArtifactSelection()
        #expect(model.projects.artifactSelection.isEmpty)
        // The registry-target selection is untouched by either call.
        #expect(model.selection.ids.contains("cache"))
    }

    @Test("Projects are unselectable while a scan is in flight")
    func projectUnselectableWhileScanning() async {
        let store = TemporaryDefaults()
        let fixture = project(
            "/dev/app", devRoot: "/dev",
            artifacts: [artifact("/dev/app/node_modules", bytes: 500)]
        )
        let gate = Mutex(false)
        let model = AppModel(
            targets: [target("cache")],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in
                    while !gate.withLock({ $0 }) { usleep(10_000) }
                    return measured(100)
                },
                projectScan: { root in DevRootScan(root: root, projects: [fixture]) }
            )
        )
        model.projects.addDevRoot(URL(filePath: "/dev"))
        #expect(model.projects.isProjectSelectable(fixture))    // idle: selectable

        model.scanner.scanAll()
        #expect(model.activity.isScanning)
        #expect(!model.projects.isProjectSelectable(fixture))   // busy: not selectable
        model.projects.setProjectSelected(fixture, true)        // refused while busy
        #expect(model.projects.artifactSelection.isEmpty)

        gate.withLock { $0 = true }
        await model.scanner.scanTask?.value
        #expect(model.projects.isProjectSelectable(fixture))    // idle again
    }
}
