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
        first.projects.addDevRoot(URL(filePath: "/Users/dev/Source"))
        #expect(first.projects.devRoots.map(\.path) == ["/Users/dev/Source"])

        let second = AppModel(targets: [], defaults: store.defaults)
        #expect(second.projects.devRoots.map(\.path) == ["/Users/dev/Source"])
    }

    @Test("Nested dev roots are deduplicated")
    func nestedRootsDeduplicated() {
        let store = TemporaryDefaults()
        let model = AppModel(targets: [], defaults: store.defaults)
        model.projects.addDevRoot(URL(filePath: "/Users/dev/Source"))

        // A child of an existing root is refused.
        model.projects.addDevRoot(URL(filePath: "/Users/dev/Source/sub"))
        #expect(model.projects.devRoots.count == 1)

        // A parent replaces the roots it contains.
        model.projects.addDevRoot(URL(filePath: "/Users/dev"))
        #expect(model.projects.devRoots.map(\.path) == ["/Users/dev"])
    }

    @Test("Scanning includes configured dev roots")
    func scanIncludesDevRoots() async {
        let store = TemporaryDefaults()
        let fixture = project(
            "/dev/app", devRoot: "/dev",
            artifacts: [artifact("/dev/app/node_modules", bytes: 500)]
        )
        let clean = project("/dev/tidy", devRoot: "/dev", artifacts: [])
        let model = AppModel(
            targets: [target("cache")],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) },
                projectScan: { root in
                    DevRootScan(root: root, projects: [fixture, clean])
                }
            )
        )
        model.projects.addDevRoot(URL(filePath: "/dev"))

        model.scanner.scanAll()
        await model.scanner.scanTask?.value

        #expect(model.projects.projectScans.count == 1)
        #expect(model.projects.discovered.map(\.name) == ["app", "tidy"])
        #expect(model.projects.projectArtifactBytes == 500)
        #expect(model.projects.projectsWithArtifactsCount == 1)   // artifact-free "tidy" not counted
        #expect(model.totalFoundBytes == 600)   // 100 target + 500 artifacts
        #expect(model.cleanableBytes == 600)
        #expect(model.results.lastScanWasComplete)
    }

    @Test("Without dev roots the scan runs exactly as before")
    func noRootsNoProjectScan() async {
        let store = TemporaryDefaults()
        let calls = Mutex(0)
        let model = AppModel(
            targets: [target("cache")],
            defaults: store.defaults,
            executors: Executors(
                scan: { _ in measured(100) },
                projectScan: { root in
                    calls.withLock { $0 += 1 }
                    return DevRootScan(root: root, projects: [])
                }
            )
        )

        model.scanner.scanAll()
        await model.scanner.scanTask?.value

        #expect(calls.withLock { $0 } == 0)
        #expect(model.projects.projectScans.isEmpty)
        #expect(model.totalFoundBytes == 100)
    }

    @Test("A failed root surfaces its failure message")
    func failedRootSurfaces() async {
        let store = TemporaryDefaults()
        let model = AppModel(
            targets: [],
            defaults: store.defaults,
            executors: Executors(
                projectScan: { root in
                    DevRootScan(root: root, projects: [], failureMessage: "gone")
                }
            )
        )
        model.projects.addDevRoot(URL(filePath: "/missing"))

        model.scanner.scanAll()
        await model.scanner.scanTask?.value

        #expect(model.projects.projectScans.first?.failureMessage == "gone")
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
            executors: Executors(
                projectScan: { root in DevRootScan(root: root, projects: [fixture]) }
            )
        )
        model.projects.addDevRoot(URL(filePath: "/dev"))
        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.projects.setArtifactSelected(fixture.artifacts[0], true)
        #expect(model.projects.selectedArtifactBytes == 500)

        model.projects.removeDevRoot(URL(filePath: "/dev"))

        #expect(model.projects.devRoots.isEmpty)
        #expect(model.projects.projectScans.isEmpty)
        #expect(model.projects.selectedArtifactBytes == 0)
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
            executors: Executors(
                scan: { _ in measured(100) },
                projectScan: { root in DevRootScan(root: root, projects: [fixture]) }
            )
        )
        model.projects.addDevRoot(URL(filePath: "/dev"))
        model.scanner.scanAll()
        await model.scanner.scanTask?.value

        // Post-scan auto-selection ticked the safe target (100).
        #expect(model.selectedBytes == 100)
        model.projects.setArtifactSelected(fixture.artifacts[0], true)
        #expect(model.selectedBytes == 600)
        #expect(model.projects.selectedArtifactBytes == 500)
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
        #expect(!model.projects.isProjectStale(fresh, now: now))
        #expect(model.projects.isProjectStale(stale, now: now))
        #expect(!model.projects.isProjectStale(unknown, now: now))  // unknown ≠ stale
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

        model.cleanSelected()
        await model.cleanTask?.value

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

        model.cleanSelected()

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

        model.cleanSelected(scope: .targets(["cache"]))
        await model.cleanTask?.value

        #expect(cleanCalls.withLock { $0 } == 0)
        #expect(model.projects.isArtifactSelected(nodeModules))  // selection survives
    }

    // MARK: - ~/.claude exclusion

    @Test("Claude Code's own data folder is refused as a dev root")
    func claudeFolderRefused() {
        let store = TemporaryDefaults()
        let model = AppModel(targets: [], defaults: store.defaults)
        let home = FileManager.default.homeDirectoryForCurrentUser

        model.projects.addDevRoot(home.appending(path: ".claude"))
        #expect(model.projects.devRoots.isEmpty)

        model.projects.addDevRoot(home.appending(path: ".claude/plugins/foo"))
        #expect(model.projects.devRoots.isEmpty)

        // A sibling folder is unaffected.
        model.projects.addDevRoot(home.appending(path: "Source"))
        #expect(model.projects.devRoots.map(\.path) == [
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
        model.projects.addDevRoot(link)

        #expect(model.projects.devRoots.map(\.path) == [resolvedReal.path])
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
        model.projects.addDevRoot(link)
        model.projects.addDevRoot(resolvedReal)

        #expect(model.projects.devRoots.count == 1)
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
            executors: Executors(
                projectScan: { root in DevRootScan(root: root, projects: [fixture]) }
            )
        )
        model.projects.addDevRoot(link)
        model.scanner.scanAll()
        await model.scanner.scanTask?.value
        model.projects.setArtifactSelected(nodeModules, true)
        #expect(model.hasCleanableSelection)

        // The root is removed by its resolved form, matching what's
        // actually stored in `devRoots`.
        model.projects.removeDevRoot(resolvedReal)

        #expect(model.projects.artifactSelection.isEmpty)
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
            executors: Executors(
                projectScan: { root in
                    DevRootScan(root: root, projects: [small, empty, big])
                }
            )
        )
        model.projects.addDevRoot(URL(filePath: "/dev"))
        model.scanner.scanAll()
        await model.scanner.scanTask?.value

        #expect(model.projects.largestProjects(limit: 5).map(\.name) == ["big", "small"])
        #expect(model.projects.largestProjects(limit: 1).map(\.name) == ["big"])
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
            executors: Executors(
                scan: { t in t.id == "cache" ? measured(100) : measured(0) },
                projectScan: { root in
                    DevRootScan(root: root, projects: [big, small])
                }
            )
        )
        model.projects.addDevRoot(URL(filePath: "/dev"))
        model.scanner.scanAll()
        await model.scanner.scanTask?.value

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

        model.cleanSelected(scope: .projectArtifacts("/dev/app"))
        await model.cleanTask?.value

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

        model.cleanSelected(scope: .projectArtifacts("/dev/app"))

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

        model.cleanSelected(scope: .projectArtifacts("/dev/gone"))
        await model.cleanTask?.value

        #expect(cleanCalls.withLock { $0 } == 0)
        #expect(model.activity.lastCleanSummary == nil)
        #expect(model.projects.isArtifactSelected(nodeModules))
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
