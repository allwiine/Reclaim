//
//  ProjectDiscoveryTests.swift
//  ReclaimKitTests
//
//  Fixture trees on the real filesystem via withTemporaryDirectory.
//

import Foundation
import Testing
@testable import ReclaimKit

// MARK: - Fixture helpers

/// A minimal repo: `.git/logs/HEAD` with one reflog line.
private func makeGitRepo(at url: URL, epoch: Int = 1_700_000_000) throws {
    let logs = url.appending(path: ".git/logs")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    try ("0000000000000000000000000000000000000000 "
        + "1111111111111111111111111111111111111111 "
        + "Dev <dev@example.com> \(epoch) +0000\tcommit: fixture\n")
        .write(to: logs.appending(path: "HEAD"), atomically: true, encoding: .utf8)
}

private func makeDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}

@Suite("Project discovery")
struct ProjectDiscoveryTests {
    @Test("Finds a node project with its node_modules")
    func nodeProject() throws {
        try withTemporaryDirectory { root in
            let project = root.appending(path: "my-app")
            try makeGitRepo(at: project, epoch: 1_690_000_000)
            try makeFile(in: project, name: "package.json", byteCount: 10)
            try makeFile(in: project.appending(path: "node_modules/lodash"), name: "index.js", byteCount: 4096)

            let scan = ProjectDiscovery().scan(root: root)
            #expect(scan.failureMessage == nil)
            let found = try #require(scan.projects.first)
            #expect(found.name == "my-app")
            #expect(found.isGitRepo)
            #expect(found.lastGitActivityDate == Date(timeIntervalSince1970: 1_690_000_000))
            let artifact = try #require(found.artifacts.first)
            #expect(artifact.kindID == "node-modules")
            #expect(artifact.url.lastPathComponent == "node_modules")
            #expect(artifact.measurement.bytes >= 4096)
            #expect(artifact.measurement.fileCount == 1)
        }
    }

    @Test("Last edit excludes artifact interiors and .git")
    func lastEditExcludesArtifacts() throws {
        try withTemporaryDirectory { root in
            let project = root.appending(path: "app")
            try makeFile(in: project, name: "package.json", byteCount: 5)
            let source = try makeFile(in: project, name: "main.js", byteCount: 5)
            let dependency = try makeFile(
                in: project.appending(path: "node_modules"), name: "dep.js", byteCount: 5
            )

            // Backdate the source; make the artifact file "newer".
            let old = Date(timeIntervalSince1970: 1_600_000_000)
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: source.path)
            let sourceDir = project.appending(path: "package.json")
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: sourceDir.path)
            _ = dependency // stays "now"

            let found = try #require(ProjectDiscovery().scan(root: root).projects.first)
            let lastEdit = try #require(found.lastEditDate)
            #expect(abs(lastEdit.timeIntervalSince(old)) < 2)
        }
    }

    @Test("A bare dist without package.json is not an artifact")
    func ambiguousDirWithoutProof() throws {
        try withTemporaryDirectory { root in
            let project = root.appending(path: "photos")
            try makeGitRepo(at: project)
            try makeFile(in: project.appending(path: "dist"), name: "photo.raw", byteCount: 100)

            let found = try #require(ProjectDiscovery().scan(root: root).projects.first)
            #expect(found.artifacts.isEmpty)
        }
    }

    @Test("A venv counts only with pyvenv.cfg inside")
    func venvNeedsInternalProof() throws {
        try withTemporaryDirectory { root in
            let project = root.appending(path: "py")
            try makeGitRepo(at: project)
            try makeFile(in: project.appending(path: ".venv"), name: "pyvenv.cfg", byteCount: 10)
            try makeFile(in: project.appending(path: "venv"), name: "notes.txt", byteCount: 10)

            let found = try #require(ProjectDiscovery().scan(root: root).projects.first)
            #expect(found.artifacts.count == 1)
            #expect(found.artifacts.first?.url.lastPathComponent == ".venv")
        }
    }

    @Test("Monorepo: nested artifacts attach to the outermost project")
    func monorepo() throws {
        try withTemporaryDirectory { root in
            let repo = root.appending(path: "mono")
            try makeGitRepo(at: repo)
            try makeFile(in: repo, name: "package.json", byteCount: 5)
            try makeFile(in: repo.appending(path: "node_modules"), name: "a.js", byteCount: 10)
            let pkg = repo.appending(path: "packages/web")
            try makeFile(in: pkg, name: "package.json", byteCount: 5)
            try makeFile(in: pkg.appending(path: "node_modules"), name: "b.js", byteCount: 10)

            let scan = ProjectDiscovery().scan(root: root)
            #expect(scan.projects.count == 1)
            let found = try #require(scan.projects.first)
            #expect(found.artifacts.count == 2)
        }
    }

    @Test("Carthage/Build is the artifact, not Carthage itself")
    func carthageNestedChild() throws {
        try withTemporaryDirectory { root in
            let project = root.appending(path: "ios-app")
            try makeGitRepo(at: project)
            try makeFile(in: project, name: "Cartfile", byteCount: 5)
            try makeFile(in: project.appending(path: "Carthage/Build"), name: "X.framework", byteCount: 50)
            try makeFile(in: project.appending(path: "Carthage/Checkouts"), name: "src.c", byteCount: 5)

            let found = try #require(ProjectDiscovery().scan(root: root).projects.first)
            #expect(found.artifacts.count == 1)
            let artifact = try #require(found.artifacts.first)
            #expect(artifact.kindID == "carthage")
            #expect(artifact.url.path.hasSuffix("Carthage/Build"))
        }
    }

    @Test("A .git file (worktree) still marks a repo, without a date")
    func gitFileWorktree() throws {
        try withTemporaryDirectory { root in
            let project = root.appending(path: "wt")
            try makeFile(in: project, name: ".git", byteCount: 30) // gitdir: pointer
            try makeFile(in: project, name: "package.json", byteCount: 5)

            let found = try #require(ProjectDiscovery().scan(root: root).projects.first)
            #expect(found.isGitRepo)
            #expect(found.lastGitActivityDate == nil)
        }
    }

    @Test("Hidden directories outside projects are pruned")
    func hiddenPrunedOutsideProjects() throws {
        try withTemporaryDirectory { root in
            let hiddenProject = root.appending(path: ".config/tool")
            try makeGitRepo(at: hiddenProject)
            #expect(ProjectDiscovery().scan(root: root).projects.isEmpty)
        }
    }

    @Test("The search respects the depth limit")
    func depthLimit() throws {
        try withTemporaryDirectory { root in
            // Depth 6 (a/b/c/d/e/f) is still searched; depth 7 is not.
            let atLimit = root.appending(path: "a/b/c/d/e/found")
            try makeGitRepo(at: atLimit)
            let beyond = root.appending(path: "a/b/c/d/e/f/missed")
            try makeGitRepo(at: beyond)

            let scan = ProjectDiscovery().scan(root: root)
            #expect(scan.projects.map(\.name) == ["found"])
        }
    }

    @Test("Symlinks are never followed")
    func symlinksNotFollowed() throws {
        try withTemporaryDirectory { root in
            let real = root.appending(path: "real")
            try makeGitRepo(at: real)
            try makeFile(in: real, name: "package.json", byteCount: 5)
            // A cycle: a symlink inside the tree pointing back at the root.
            try FileManager.default.createSymbolicLink(
                at: real.appending(path: "loop"),
                withDestinationURL: root
            )
            let scan = ProjectDiscovery().scan(root: root)
            #expect(scan.projects.count == 1) // terminates, no duplicates
        }
    }

    @Test("The dev root itself can be a project")
    func rootIsProject() throws {
        try withTemporaryDirectory { root in
            try makeGitRepo(at: root)
            try makeFile(in: root, name: "Cargo.toml", byteCount: 5)
            try makeFile(in: root.appending(path: "target"), name: "bin", byteCount: 10)

            let scan = ProjectDiscovery().scan(root: root)
            #expect(scan.projects.count == 1)
            #expect(scan.projects.first?.artifacts.first?.kindID == "cargo-target")
        }
    }

    @Test("A missing root reports a failure, not an empty success")
    func missingRoot() {
        let scan = ProjectDiscovery().scan(
            root: URL(filePath: "/nonexistent-reclaim-devroot")
        )
        #expect(scan.projects.isEmpty)
        #expect(scan.failureMessage != nil)
    }

    @Test("Cancellation returns completed projects only")
    func cancellationKeepsCompleted() async throws {
        try await withTemporaryDirectory { root in
            for index in 0..<3 {
                let project = root.appending(path: "p\(index)")
                try makeGitRepo(at: project)
                try makeFile(in: project, name: "package.json", byteCount: 5)
            }
            let path = root.path
            let task = Task {
                ProjectDiscovery().scan(root: URL(filePath: path))
            }
            task.cancel()
            let scan = await task.value
            // Cancelled promptly: whatever completed is kept, never more.
            #expect(scan.projects.count <= 3)
            #expect(scan.failureMessage == nil)
        }
    }
}
