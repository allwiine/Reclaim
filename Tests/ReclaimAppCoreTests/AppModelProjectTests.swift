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

/// A fresh temporary directory, removed by the caller when done.
private func makeTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "AppModelProjectTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
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
            projectScanExecutor: { root in
                let pass = scanCount.withLock { count in
                    count += 1
                    return count
                }
                return DevRootScan(root: root, projects: pass == 1 ? [before] : [after])
            },
            artifactCleanExecutor: { paths, _ in
                cleanedPaths.withLock { $0.append(contentsOf: paths.map(\.path)) }
                return CleanOutcome(removedItems: paths.count)
            },
            historyStore: temporaryHistoryStore()
        )
        model.addDevRoot(URL(filePath: "/dev"))
        model.scanAll()
        await model.scanTask?.value
        model.setArtifactSelected(nodeModules, true)

        model.cleanSelected()
        await model.cleanTask?.value

        // The engine saw exactly the scan-time snapshot path.
        #expect(cleanedPaths.withLock { $0 } == ["/dev/app/node_modules"])
        // The fixture path does not exist on disk, so removal verifies.
        let summary = try #require(model.lastCleanSummary)
        #expect(summary.cleanedArtifacts.count == 1)
        #expect(summary.cleanedArtifacts.first?.bytesFreed == 500)
        #expect(summary.reclaimedBytes == 500)
        #expect(summary.itemsRemoved == 1)
        // The affected root was re-discovered (executor ran twice).
        #expect(scanCount.withLock { $0 } == 2)
        #expect(model.projects.first?.artifacts.isEmpty == true)
        // Selection cleared; history recorded the artifact.
        #expect(model.artifactSelection.isEmpty)
        #expect(model.history.first?.items?.contains {
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
            projectScanExecutor: { root in DevRootScan(root: root, projects: [fixture]) },
            artifactCleanExecutor: { paths, _ in
                cleanCalls.withLock { $0 += 1 }
                return CleanOutcome(removedItems: paths.count)
            },
            historyStore: temporaryHistoryStore()
        )
        model.dryRun = true
        model.addDevRoot(URL(filePath: "/dev"))
        model.scanAll()
        await model.scanTask?.value
        model.setArtifactSelected(nodeModules, true)

        model.cleanSelected()

        #expect(cleanCalls.withLock { $0 } == 0)
        let summary = try #require(model.lastCleanSummary)
        #expect(summary.isDryRun)
        #expect(summary.cleanedArtifacts.first?.bytesFreed == 500)
        #expect(summary.reclaimedBytes == 500)
        // Dry run leaves the selection intact.
        #expect(model.isArtifactSelected(nodeModules))
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
            scanExecutor: { _ in measured(100) },
            cleanExecutor: { _, _, _ in CleanOutcome(removedItems: 1) },
            projectScanExecutor: { root in DevRootScan(root: root, projects: [fixture]) },
            artifactCleanExecutor: { paths, _ in
                cleanCalls.withLock { $0 += 1 }
                return CleanOutcome(removedItems: paths.count)
            },
            historyStore: temporaryHistoryStore()
        )
        model.addDevRoot(URL(filePath: "/dev"))
        model.scanAll()
        await model.scanTask?.value
        model.setArtifactSelected(nodeModules, true)

        model.cleanSelected(limitedTo: ["cache"])
        await model.cleanTask?.value

        #expect(cleanCalls.withLock { $0 } == 0)
        #expect(model.isArtifactSelected(nodeModules))  // selection survives
    }

    // MARK: - ~/.claude exclusion

    @Test("Claude Code's own data folder is refused as a dev root")
    func claudeFolderRefused() {
        let store = TemporaryDefaults()
        let model = AppModel(targets: [], defaults: store.defaults)
        let home = FileManager.default.homeDirectoryForCurrentUser

        model.addDevRoot(home.appending(path: ".claude"))
        #expect(model.devRoots.isEmpty)

        model.addDevRoot(home.appending(path: ".claude/plugins/foo"))
        #expect(model.devRoots.isEmpty)

        // A sibling folder is unaffected.
        model.addDevRoot(home.appending(path: "Source"))
        #expect(model.devRoots.map(\.path) == [
            home.appending(path: "Source").resolvingSymlinksInPath().path,
        ])
    }

    // MARK: - Symlinked roots

    @Test("A symlinked root is stored resolved")
    func symlinkedRootResolves() throws {
        let store = TemporaryDefaults()
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let real = base.appending(path: "real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let resolvedReal = real.resolvingSymlinksInPath()
        let link = base.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let model = AppModel(targets: [], defaults: store.defaults)
        model.addDevRoot(link)

        #expect(model.devRoots.map(\.path) == [resolvedReal.path])
    }

    @Test("A symlinked root and its resolved twin dedup to one root")
    func symlinkedRootDedups() throws {
        let store = TemporaryDefaults()
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let real = base.appending(path: "real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let resolvedReal = real.resolvingSymlinksInPath()
        let link = base.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let model = AppModel(targets: [], defaults: store.defaults)
        model.addDevRoot(link)
        model.addDevRoot(resolvedReal)

        #expect(model.devRoots.count == 1)
    }

    @Test("Removing a symlinked root's resolved twin clears its artifact selection")
    func removeSymlinkedRootClearsSelection() async throws {
        let store = TemporaryDefaults()
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let real = base.appending(path: "real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let resolvedReal = real.resolvingSymlinksInPath()
        let link = base.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        // Discovery resolves symlinks, so the fixture project/artifact
        // live under the RESOLVED path even though the configured root
        // is the symlink.
        let artifactURL = resolvedReal.appending(path: "app/node_modules")
        let nodeModules = artifact(artifactURL.path, bytes: 500)
        let fixture = project(
            resolvedReal.appending(path: "app").path,
            devRoot: resolvedReal.path,
            artifacts: [nodeModules]
        )
        let model = AppModel(
            targets: [],
            defaults: store.defaults,
            projectScanExecutor: { root in DevRootScan(root: root, projects: [fixture]) }
        )
        model.addDevRoot(link)
        model.scanAll()
        await model.scanTask?.value
        model.setArtifactSelected(nodeModules, true)
        #expect(model.hasCleanableSelection)

        // The root is removed by its resolved form, matching what's
        // actually stored in `devRoots`.
        model.removeDevRoot(resolvedReal)

        #expect(model.artifactSelection.isEmpty)
        #expect(!model.hasCleanableSelection)
    }

    @Test("Largest projects are sorted by size and exclude artifact-free ones")
    func largestProjects() async {
        let store = TemporaryDefaults()
        let small = project(
            "/dev/small", devRoot: "/dev",
            artifacts: [artifact("/dev/small/node_modules", bytes: 500)]
        )
        let empty = project("/dev/empty", devRoot: "/dev", artifacts: [])
        let big = project(
            "/dev/big", devRoot: "/dev",
            artifacts: [artifact("/dev/big/node_modules", bytes: 900)]
        )
        let model = AppModel(
            targets: [],
            defaults: store.defaults,
            projectScanExecutor: { root in
                DevRootScan(root: root, projects: [small, empty, big])
            }
        )
        model.addDevRoot(URL(filePath: "/dev"))
        model.scanAll()
        await model.scanTask?.value

        #expect(model.largestProjects(limit: 5).map(\.name) == ["big", "small"])
        #expect(model.largestProjects(limit: 1).map(\.name) == ["big"])
    }

    @Test("Largest findings mix registry targets and projects by size")
    func largestFindingsMix() async {
        let store = TemporaryDefaults()
        let big = project(
            "/dev/big", devRoot: "/dev",
            artifacts: [artifact("/dev/big/node_modules", bytes: 500)]
        )
        let small = project(
            "/dev/small", devRoot: "/dev",
            artifacts: [artifact("/dev/small/node_modules", bytes: 50)]
        )
        let model = AppModel(
            targets: [target("cache"), target("nothing")],
            defaults: store.defaults,
            scanExecutor: { t in t.id == "cache" ? measured(100) : measured(0) },
            projectScanExecutor: { root in
                DevRootScan(root: root, projects: [big, small])
            }
        )
        model.addDevRoot(URL(filePath: "/dev"))
        model.scanAll()
        await model.scanTask?.value

        let findings = model.largestFindings(limit: 6)
        #expect(findings.map(\.id) == ["project:/dev/big", "target:cache", "project:/dev/small"])
        #expect(findings.map(\.bytes) == [500, 100, 50])
        #expect(model.largestFindings(limit: 1).map(\.id) == ["project:/dev/big"])
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
            projectScanExecutor: { root in DevRootScan(root: root, projects: [fixture]) }
        )
        model.addDevRoot(URL(filePath: "/dev"))
        model.scanAll()
        await model.scanTask?.value

        #expect(model.isProjectSelectable(fixture))
        #expect(!model.isProjectSelected(fixture))
        #expect(!model.isProjectPartiallySelected(fixture))
        #expect(model.partialSelectionCounts(of: fixture) == nil)

        model.setArtifactSelected(nodeModules, true)
        #expect(!model.isProjectSelected(fixture))
        #expect(model.isProjectPartiallySelected(fixture))
        let counts = try #require(model.partialSelectionCounts(of: fixture))
        #expect(counts.selected == 1)
        #expect(counts.total == 2)          // the empty artifact never counts
        #expect(model.selectedArtifactBytes(of: fixture) == 500)

        model.setProjectSelected(fixture, true)
        #expect(model.isProjectSelected(fixture))
        #expect(!model.isProjectPartiallySelected(fixture))
        // Full selection is not "partial": counts are nil, like targets.
        #expect(model.partialSelectionCounts(of: fixture) == nil)
        // The empty artifact stays unticked (nothing to free).
        #expect(!model.isArtifactSelected(empty))
        #expect(model.selectedArtifactBytes(of: fixture) == 800)
        #expect(model.selectedArtifacts(of: fixture).map(\.id) ==
            ["/dev/app/node_modules", "/dev/app/.build"])

        model.setProjectSelected(fixture, false)
        #expect(model.artifactSelection.isEmpty)
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
            projectScanExecutor: { root in
                DevRootScan(root: root, projects: [bare, onlyEmpty])
            }
        )
        model.addDevRoot(URL(filePath: "/dev"))
        model.scanAll()
        await model.scanTask?.value

        #expect(!model.isProjectSelectable(bare))
        #expect(!model.isProjectSelectable(onlyEmpty))
        model.setProjectSelected(onlyEmpty, true)       // refused per artifact
        #expect(model.artifactSelection.isEmpty)
        #expect(model.selectableArtifactCount == 0)
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
            scanExecutor: { _ in measured(100) },
            projectScanExecutor: { root in
                DevRootScan(root: root, projects: [app, lib])
            }
        )
        model.addDevRoot(URL(filePath: "/dev"))
        model.scanAll()
        await model.scanTask?.value
        // Post-scan auto-selection ticked the safe registry target.
        #expect(model.selection.contains("cache"))

        model.selectAllArtifacts()
        #expect(model.selectedArtifacts.map(\.id).sorted() ==
            ["/dev/app/node_modules", "/dev/lib/.build"])
        #expect(model.selectableArtifactCount == 2)

        model.clearArtifactSelection()
        #expect(model.artifactSelection.isEmpty)
        // The registry-target selection is untouched by either call.
        #expect(model.selection.contains("cache"))
    }
}
