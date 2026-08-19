//
//  ProjectDiscoveryTests.swift
//  ReclaimAppCoreTests
//
//  Dev-folder feature orchestration against stubbed executors: how a
//  scan discovers projects under the configured dev roots, staleness,
//  and size-ranked listings. Split out of ProjectsTests to stay under
//  the file-length gate.
//

import Foundation
import ReclaimKit
import Synchronization
import Testing
@testable import ReclaimAppCore

@MainActor
@Suite("Projects — discovery")
struct ProjectDiscoveryTests {
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
}
