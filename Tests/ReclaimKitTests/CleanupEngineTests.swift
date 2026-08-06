//
//  CleanupEngineTests.swift
//  ReclaimKitTests
//
//  Engine behavior is verified against a mock remover — no test ever
//  touches the real Trash.
//

import Foundation
import Synchronization
import Testing
@testable import ReclaimKit

// MARK: - Mock

/// Records every disposal instead of touching the filesystem.
/// `Mutex` keeps it truly `Sendable` under strict concurrency.
private final class MockRemover: FileRemoving, Sendable {
    struct StubError: Error, LocalizedError {
        var errorDescription: String? { "Stubbed failure" }
    }

    private struct State: Sendable {
        var trashed: [URL] = []
        var deleted: [URL] = []
    }

    private let state = Mutex(State())
    private let children: [URL: [URL]]
    private let failingPaths: Set<URL>

    init(children: [URL: [URL]] = [:], failingPaths: Set<URL> = []) {
        self.children = children
        self.failingPaths = failingPaths
    }

    var trashed: [URL] { state.withLock { $0.trashed } }
    var deleted: [URL] { state.withLock { $0.deleted } }

    func trash(_ url: URL) throws {
        if failingPaths.contains(url) { throw StubError() }
        state.withLock { $0.trashed.append(url) }
    }

    func delete(_ url: URL) throws {
        if failingPaths.contains(url) { throw StubError() }
        state.withLock { $0.deleted.append(url) }
    }

    func childrenOfDirectory(_ url: URL) throws -> [URL] {
        guard let entries = children[url] else { throw StubError() }
        return entries
    }
}

// MARK: - Fixtures

private func makeTarget(strategy: CleanupStrategy) -> CleanupTarget {
    CleanupTarget(
        id: "test-target",
        name: "Test target",
        summary: "Fixture",
        category: .otherTools,
        safety: .safe,
        pathPatterns: ["~/fixture"],
        strategy: strategy
    )
}

// MARK: - Tests

@Suite("Cleanup engine")
struct CleanupEngineTests {
    private let cacheRoot = URL(filePath: "/tmp/fixture/cache")
    private var childA: URL { cacheRoot.appending(path: "a") }
    private var childB: URL { cacheRoot.appending(path: "b") }

    @Test("removeContents trashes children but keeps the directory")
    func removeContentsKeepsRoot() {
        let remover = MockRemover(children: [cacheRoot: [childA, childB]])
        let engine = CleanupEngine(remover: remover)

        let outcome = engine.clean(
            makeTarget(strategy: .removeContents),
            resolvedPaths: [cacheRoot],
            disposal: .trash
        )

        #expect(outcome.removedItems == 2)
        #expect(outcome.failures.isEmpty)
        #expect(remover.trashed == [childA, childB])
        #expect(!remover.trashed.contains(cacheRoot))
        #expect(remover.deleted.isEmpty)
    }

    @Test("removePaths removes the paths themselves")
    func removePathsRemovesRoot() {
        let remover = MockRemover()
        let engine = CleanupEngine(remover: remover)

        let outcome = engine.clean(
            makeTarget(strategy: .removePaths),
            resolvedPaths: [cacheRoot],
            disposal: .trash
        )

        #expect(outcome.removedItems == 1)
        #expect(remover.trashed == [cacheRoot])
    }

    @Test("Disposal setting routes to delete instead of trash")
    func permanentDeletion() {
        let remover = MockRemover(children: [cacheRoot: [childA]])
        let engine = CleanupEngine(remover: remover)

        _ = engine.clean(
            makeTarget(strategy: .removeContents),
            resolvedPaths: [cacheRoot],
            disposal: .delete
        )

        #expect(remover.deleted == [childA])
        #expect(remover.trashed.isEmpty)
    }

    @Test("Per-item failures are collected without aborting the pass")
    func failuresAreCollected() {
        let remover = MockRemover(
            children: [cacheRoot: [childA, childB]],
            failingPaths: [childA]
        )
        let engine = CleanupEngine(remover: remover)

        let outcome = engine.clean(
            makeTarget(strategy: .removeContents),
            resolvedPaths: [cacheRoot],
            disposal: .trash
        )

        #expect(outcome.removedItems == 1)
        #expect(outcome.failures.count == 1)
        #expect(outcome.failures.first?.path == childA.path)
        #expect(remover.trashed == [childB])
    }

    @Test("Manual targets are refused")
    func manualTargetsRefuse() {
        let remover = MockRemover()
        let engine = CleanupEngine(remover: remover)

        let outcome = engine.clean(
            makeTarget(strategy: .manual(instructions: "Use the tool itself.")),
            resolvedPaths: [cacheRoot],
            disposal: .trash
        )

        #expect(outcome.removedItems == 0)
        #expect(outcome.failures.count == 1)
        #expect(remover.trashed.isEmpty)
        #expect(remover.deleted.isEmpty)
    }

    @Test("Unreadable directories surface as failures")
    func unreadableDirectory() {
        // No children registered for cacheRoot → listing throws.
        let remover = MockRemover()
        let engine = CleanupEngine(remover: remover)

        let outcome = engine.clean(
            makeTarget(strategy: .removeContents),
            resolvedPaths: [cacheRoot],
            disposal: .trash
        )

        #expect(outcome.removedItems == 0)
        #expect(outcome.failures.count == 1)
    }
}
