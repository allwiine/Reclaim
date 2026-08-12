//
//  CleanupEngineRemoveTests.swift
//  ReclaimKitTests
//
//  The path-list entry point used by the dev-folder artifact cleaner.
//

import Foundation
import Synchronization
import Testing
import ReclaimKit

private final class RecordingRemover: FileRemoving {
    let trashed = Mutex<[String]>([])
    let deleted = Mutex<[String]>([])
    let failingPaths: Set<String>

    init(failingPaths: Set<String> = []) {
        self.failingPaths = failingPaths
    }

    func trash(_ url: URL) throws {
        if failingPaths.contains(url.path) { throw CocoaError(.fileWriteNoPermission) }
        trashed.withLock { $0.append(url.path) }
    }

    func delete(_ url: URL) throws {
        if failingPaths.contains(url.path) { throw CocoaError(.fileWriteNoPermission) }
        deleted.withLock { $0.append(url.path) }
    }
}

@Suite("Cleanup engine — remove(paths:)")
struct CleanupEngineRemoveTests {
    @Test("Disposes each path via the chosen disposal")
    func disposesEachPath() {
        let remover = RecordingRemover()
        let engine = CleanupEngine(remover: remover)
        let paths = [URL(filePath: "/p/node_modules"), URL(filePath: "/p/.build")]

        let outcome = engine.remove(paths: paths, disposal: .trash)

        #expect(outcome.removedItems == 2)
        #expect(outcome.failures.isEmpty)
        #expect(remover.trashed.withLock { $0 } == ["/p/node_modules", "/p/.build"])
        #expect(remover.deleted.withLock { $0 }.isEmpty)
    }

    @Test("Permanent disposal uses delete")
    func permanentDisposal() {
        let remover = RecordingRemover()
        let engine = CleanupEngine(remover: remover)

        let outcome = engine.remove(paths: [URL(filePath: "/p/target")], disposal: .delete)

        #expect(outcome.removedItems == 1)
        #expect(remover.deleted.withLock { $0 } == ["/p/target"])
    }

    @Test("One locked path does not abort the pass")
    func bestEffort() {
        let remover = RecordingRemover(failingPaths: ["/p/locked"])
        let engine = CleanupEngine(remover: remover)
        let paths = [URL(filePath: "/p/locked"), URL(filePath: "/p/free")]

        let outcome = engine.remove(paths: paths, disposal: .trash)

        #expect(outcome.removedItems == 1)
        #expect(outcome.failures.count == 1)
        #expect(outcome.failures.first?.path == "/p/locked")
        #expect(remover.trashed.withLock { $0 } == ["/p/free"])
    }
}
