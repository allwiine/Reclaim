//
//  AppModelProjectTests.swift
//  ReclaimAppCoreTests
//
//  Dev-folder feature orchestration against stubbed executors.
//

import Foundation
import ReclaimKit
import Synchronization
import Testing
@testable import ReclaimAppCore

// MARK: - Fixtures

private func target(_ id: String) -> CleanupTarget {
    CleanupTarget(
        id: id, name: id, summary: "Fixture", category: .otherTools,
        safety: .safe, pathPatterns: ["~/\(id)"], strategy: .removeContents
    )
}

private func measured(_ bytes: Int64) -> TargetStatus {
    .measured(
        DiskMeasurement(bytes: bytes, fileCount: 1),
        resolvedPaths: [URL(filePath: "/fixture")],
        cleanupPaths: [URL(filePath: "/fixture/a")]
    )
}

private func artifact(_ path: String, bytes: Int64) -> DiscoveredArtifact {
    DiscoveredArtifact(
        kindID: "node-modules",
        url: URL(filePath: path),
        measurement: DiskMeasurement(bytes: bytes, fileCount: 1)
    )
}

private func project(
    _ path: String, devRoot: String, artifacts: [DiscoveredArtifact]
) -> DiscoveredProject {
    DiscoveredProject(
        url: URL(filePath: path), devRoot: URL(filePath: devRoot),
        isGitRepo: true, lastEditDate: nil, lastGitActivityDate: nil,
        artifacts: artifacts
    )
}

private final class TemporaryDefaults {
    let name = "AppModelProjectTests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
    }
}

private func temporaryHistoryStore() -> CleanHistoryStore {
    CleanHistoryStore(fileURL: FileManager.default.temporaryDirectory
        .appending(path: "reclaim-project-history-\(UUID().uuidString).json"))
}

// MARK: - Tests

@MainActor
@Suite("App model — dev-folder projects")
struct AppModelProjectTests {
    @Test("Dev roots persist across model instances")
    func devRootPersistence() {
        let store = TemporaryDefaults()
        let first = AppModel(targets: [], defaults: store.defaults)
        first.addDevRoot(URL(filePath: "/Users/dev/Source"))
        #expect(first.devRoots.map(\.path) == ["/Users/dev/Source"])

        let second = AppModel(targets: [], defaults: store.defaults)
        #expect(second.devRoots.map(\.path) == ["/Users/dev/Source"])
    }

    @Test("Nested dev roots are deduplicated")
    func nestedRootsDeduplicated() {
        let store = TemporaryDefaults()
        let model = AppModel(targets: [], defaults: store.defaults)
        model.addDevRoot(URL(filePath: "/Users/dev/Source"))

        // A child of an existing root is refused.
        model.addDevRoot(URL(filePath: "/Users/dev/Source/sub"))
        #expect(model.devRoots.count == 1)

        // A parent replaces the roots it contains.
        model.addDevRoot(URL(filePath: "/Users/dev"))
        #expect(model.devRoots.map(\.path) == ["/Users/dev"])
    }

    @Test("Scanning includes configured dev roots")
    func scanIncludesDevRoots() async {
        let store = TemporaryDefaults()
        let fixture = project(
            "/dev/app", devRoot: "/dev",
            artifacts: [artifact("/dev/app/node_modules", bytes: 500)]
        )
        let model = AppModel(
            targets: [target("cache")],
            defaults: store.defaults,
            scanExecutor: { _ in measured(100) },
            projectScanExecutor: { root in
                DevRootScan(root: root, projects: [fixture])
            }
        )
        model.addDevRoot(URL(filePath: "/dev"))

        model.scanAll()
        await model.scanTask?.value

        #expect(model.projectScans.count == 1)
        #expect(model.projects.map(\.name) == ["app"])
        #expect(model.projectArtifactBytes == 500)
        #expect(model.totalFoundBytes == 600)   // 100 target + 500 artifacts
        #expect(model.cleanableBytes == 600)
        #expect(model.lastScanWasComplete)
    }

    @Test("Without dev roots the scan runs exactly as before")
    func noRootsNoProjectScan() async {
        let store = TemporaryDefaults()
        let calls = Mutex(0)
        let model = AppModel(
            targets: [target("cache")],
            defaults: store.defaults,
            scanExecutor: { _ in measured(100) },
            projectScanExecutor: { root in
                calls.withLock { $0 += 1 }
                return DevRootScan(root: root, projects: [])
            }
        )

        model.scanAll()
        await model.scanTask?.value

        #expect(calls.withLock { $0 } == 0)
        #expect(model.projectScans.isEmpty)
        #expect(model.totalFoundBytes == 100)
    }

    @Test("A failed root surfaces its failure message")
    func failedRootSurfaces() async {
        let store = TemporaryDefaults()
        let model = AppModel(
            targets: [],
            defaults: store.defaults,
            projectScanExecutor: { root in
                DevRootScan(root: root, projects: [], failureMessage: "gone")
            }
        )
        model.addDevRoot(URL(filePath: "/missing"))

        model.scanAll()
        await model.scanTask?.value

        #expect(model.projectScans.first?.failureMessage == "gone")
    }

    @Test("Removing a root drops its results and selections")
    func removeRoot() async {
        let store = TemporaryDefaults()
        let fixture = project(
            "/dev/app", devRoot: "/dev",
            artifacts: [artifact("/dev/app/node_modules", bytes: 500)]
        )
        let model = AppModel(
            targets: [],
            defaults: store.defaults,
            projectScanExecutor: { root in DevRootScan(root: root, projects: [fixture]) }
        )
        model.addDevRoot(URL(filePath: "/dev"))
        model.scanAll()
        await model.scanTask?.value
        model.setArtifactSelected(fixture.artifacts[0], true)
        #expect(model.selectedArtifactBytes == 500)

        model.removeDevRoot(URL(filePath: "/dev"))

        #expect(model.devRoots.isEmpty)
        #expect(model.projectScans.isEmpty)
        #expect(model.selectedArtifactBytes == 0)
    }

    @Test("Artifact selection follows the selectability rules")
    func artifactSelection() async {
        let store = TemporaryDefaults()
        let full = artifact("/dev/app/node_modules", bytes: 500)
        let empty = artifact("/dev/app/.venv", bytes: 0)
        let fixture = project("/dev/app", devRoot: "/dev", artifacts: [full, empty])
        let model = AppModel(
            targets: [],
            defaults: store.defaults,
            projectScanExecutor: { root in DevRootScan(root: root, projects: [fixture]) }
        )
        model.addDevRoot(URL(filePath: "/dev"))
        model.scanAll()
        await model.scanTask?.value

        // Artifacts are never auto-selected after a scan.
        #expect(model.artifactSelection.isEmpty)

        #expect(model.isArtifactSelectable(full))
        #expect(!model.isArtifactSelectable(empty))    // nothing to free

        model.setArtifactSelected(full, true)
        #expect(model.isArtifactSelected(full))
        #expect(model.selectedArtifactBytes == 500)
        #expect(model.hasCleanableSelection)

        model.setArtifactSelected(empty, true)          // refused
        #expect(!model.isArtifactSelected(empty))

        model.setArtifactSelected(full, false)
        #expect(!model.hasCleanableSelection)
    }

    @Test("Selected bytes and totals include artifacts")
    func totalsIncludeArtifacts() async {
        let store = TemporaryDefaults()
        let fixture = project(
            "/dev/app", devRoot: "/dev",
            artifacts: [artifact("/dev/app/node_modules", bytes: 500)]
        )
        let model = AppModel(
            targets: [target("cache")],
            defaults: store.defaults,
            scanExecutor: { _ in measured(100) },
            projectScanExecutor: { root in DevRootScan(root: root, projects: [fixture]) }
        )
        model.addDevRoot(URL(filePath: "/dev"))
        model.scanAll()
        await model.scanTask?.value

        // Post-scan auto-selection ticked the safe target (100).
        #expect(model.selectedBytes == 100)
        model.setArtifactSelected(fixture.artifacts[0], true)
        #expect(model.selectedBytes == 600)
        #expect(model.selectedArtifactBytes == 500)
    }

    @Test("Stale detection uses the six-month threshold")
    func staleProjects() {
        let store = TemporaryDefaults()
        let model = AppModel(targets: [], defaults: store.defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = DiscoveredProject(
            url: URL(filePath: "/dev/fresh"), devRoot: URL(filePath: "/dev"),
            isGitRepo: true,
            lastEditDate: now.addingTimeInterval(-3600), lastGitActivityDate: nil,
            artifacts: []
        )
        let stale = DiscoveredProject(
            url: URL(filePath: "/dev/stale"), devRoot: URL(filePath: "/dev"),
            isGitRepo: true,
            lastEditDate: now.addingTimeInterval(-200 * 24 * 3600),
            lastGitActivityDate: nil,
            artifacts: []
        )
        let unknown = DiscoveredProject(
            url: URL(filePath: "/dev/unknown"), devRoot: URL(filePath: "/dev"),
            isGitRepo: false, lastEditDate: nil, lastGitActivityDate: nil,
            artifacts: []
        )
        #expect(!model.isProjectStale(fresh, now: now))
        #expect(model.isProjectStale(stale, now: now))
        #expect(!model.isProjectStale(unknown, now: now))  // unknown ≠ stale
    }
}
