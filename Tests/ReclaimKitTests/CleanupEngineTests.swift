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
            cleanupPaths: [childA, childB],
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
            cleanupPaths: [cacheRoot],
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
            cleanupPaths: [childA],
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
            cleanupPaths: [childA, childB],
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
            cleanupPaths: [cacheRoot],
            disposal: .trash
        )

        #expect(outcome.removedItems == 0)
        #expect(outcome.failures.count == 1)
        #expect(remover.trashed.isEmpty)
        #expect(remover.deleted.isEmpty)
    }

    @Test("Structurally excluded paths are refused, never disposed")
    func protectedPathsAreRefused() {
        let remover = MockRemover()
        let engine = CleanupEngine(remover: remover)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let protected = URL(filePath: "\(home)/.ssh/id_ed25519")
        let ordinary = URL(filePath: "\(home)/fixture/cache.bin")

        let cleanOutcome = engine.clean(
            makeTarget(strategy: .removeContents),
            cleanupPaths: [protected, ordinary],
            disposal: .trash
        )

        // The ordinary path went to Trash; the protected one was refused.
        #expect(cleanOutcome.removedItems == 1)
        #expect(remover.trashed == [ordinary])
        #expect(remover.deleted.isEmpty)
        #expect(cleanOutcome.failures.count == 1)
        #expect(cleanOutcome.failures.first?.path == protected.path)

        // The artifact entry point funnels through the same guard.
        let removeOutcome = engine.remove(paths: [protected], disposal: .delete)
        #expect(removeOutcome.removedItems == 0)
        #expect(remover.deleted.isEmpty)
        #expect(removeOutcome.failures.count == 1)
    }

    @Test("A path resolving through a symlink into a protected location is refused")
    func symlinkRedirectIntoProtectedIsRefused() throws {
        try withTemporaryDirectory { root in
            let remover = MockRemover()
            let engine = CleanupEngine(remover: remover)
            let home = FileManager.default.homeDirectoryForCurrentUser
            // Simulate a cache root swapped for a symlink into ~/.ssh
            // between scan and clean. The symlink's own path is not
            // protected, so only the engine's symlink-resolved guard
            // stops the redirection.
            let link = root.appending(path: "cache")
            try FileManager.default.createSymbolicLink(
                at: link, withDestinationURL: home.appending(path: ".ssh")
            )
            let redirected = link.appending(path: "id_ed25519")

            let outcome = engine.clean(
                makeTarget(strategy: .removeContents),
                cleanupPaths: [redirected],
                disposal: .trash
            )
            #expect(outcome.removedItems == 0)
            #expect(remover.trashed.isEmpty)
            #expect(outcome.failures.count == 1)
        }
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
            cleanupPaths: [],
            disposal: .trash
        )

        #expect(outcome.removedItems == 0)
        #expect(outcome.failures.count == 1)
        #expect(outcome.failures.first?.message.contains("stderr-flood") == true)
    }

    @Test("Tool stderr is quoted inside a localized frame")
    func stderrIsFramed() {
        let spec = CommandSpec(
            executablePath: "/bin/sh",
            arguments: ["-c", "echo boom 1>&2; exit 1"],
            displayCommand: "sh -c 'boom'"
        )
        let engine = CleanupEngine(remover: MockRemover())

        let outcome = engine.clean(
            makeTarget(strategy: .command(spec)),
            cleanupPaths: [],
            disposal: .trash
        )

        let message = outcome.failures.first?.message
        // Verbatim tool output, but never bare: the localized
        // "The tool reported:" frame marks it as a quote.
        #expect(message?.contains("boom") == true)
        #expect(message != "boom")
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
            cleanupPaths: [],
            disposal: .trash
        )

        #expect(outcome.removedItems == 1)
        #expect(outcome.failures.isEmpty)
    }

    @Test("A hung command is stopped at the deadline instead of pinning the pass")
    func hungCommandTimesOut() {
        let spec = CommandSpec(
            executablePath: "/bin/sleep",
            arguments: ["30"],
            displayCommand: "sleep 30"
        )
        let engine = CleanupEngine(remover: MockRemover(), commandTimeout: 0.4)

        let start = Date.now
        let outcome = engine.clean(
            makeTarget(strategy: .command(spec)),
            cleanupPaths: [],
            disposal: .trash
        )

        #expect(outcome.removedItems == 0)
        #expect(outcome.failures.count == 1)
        #expect(
            Date.now.timeIntervalSince(start) < 10,
            "the engine must return promptly after the deadline, not after the command"
        )
    }
}
