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
    private let failingPaths: Set<URL>

    init(failingPaths: Set<URL> = []) {
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

    @Test("removeContents disposes exactly the scan-time paths it is given")
    func removeContentsDisposesGivenPaths() {
        let remover = MockRemover()
        let engine = CleanupEngine(remover: remover)

        // The scanner snapshots the children; the engine must dispose
        // precisely those — never list the directory again at clean time.
        let outcome = engine.clean(
            makeTarget(strategy: .removeContents),
            resolvedPaths: [childA, childB],
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
        let remover = MockRemover()
        let engine = CleanupEngine(remover: remover)

        _ = engine.clean(
            makeTarget(strategy: .removeContents),
            resolvedPaths: [childA],
            disposal: .delete
        )

        #expect(remover.deleted == [childA])
        #expect(remover.trashed.isEmpty)
    }

    @Test("Per-item failures are collected without aborting the pass")
    func failuresAreCollected() {
        let remover = MockRemover(failingPaths: [childA])
        let engine = CleanupEngine(remover: remover)

        let outcome = engine.clean(
            makeTarget(strategy: .removeContents),
            resolvedPaths: [childA, childB],
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

}

// MARK: - Command execution

@Suite("Command execution")
struct CommandExecutionTests {
    @Test("A failing command that floods stderr completes and reports the error")
    func stderrFloodDoesNotDeadlock() {
        // ~330 KB of stderr — far beyond the 64 KB pipe buffer. If the
        // engine waits for exit before draining the pipe, the child
        // blocks on write and this test hangs forever.
        let spec = CommandSpec(
            executablePath: "/bin/sh",
            arguments: [
                "-c",
                "i=0; while [ $i -lt 8000 ]; do echo stderr-flood-0123456789012345678901234567 1>&2; i=$((i+1)); done; exit 3",
            ],
            displayCommand: "sh -c 'flood stderr'"
        )
        let engine = CleanupEngine(remover: MockRemover())

        let outcome = engine.clean(
            makeTarget(strategy: .command(spec)),
            resolvedPaths: [],
            disposal: .trash
        )

        #expect(outcome.removedItems == 0)
        #expect(outcome.failures.count == 1)
        #expect(outcome.failures.first?.message.contains("stderr-flood") == true)
    }

    @Test("A successful command counts as one removal")
    func successfulCommand() {
        let spec = CommandSpec(
            executablePath: "/usr/bin/true",
            arguments: [],
            displayCommand: "true"
        )
        let engine = CleanupEngine(remover: MockRemover())

        let outcome = engine.clean(
            makeTarget(strategy: .command(spec)),
            resolvedPaths: [],
            disposal: .trash
        )

        #expect(outcome.removedItems == 1)
        #expect(outcome.failures.isEmpty)
    }
}
