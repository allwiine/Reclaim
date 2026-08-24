//
//  ProjectsTests.swift
//  ReclaimAppCoreTests
//
//  Dev-folder feature orchestration against stubbed executors: dev
//  root registration, deduplication, symlink resolution and removal.
//

import Foundation
import ReclaimKit
import Synchronization
import Testing
@testable import ReclaimAppCore

@Suite("Projects — dev roots")
struct ProjectsTests {
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
}
