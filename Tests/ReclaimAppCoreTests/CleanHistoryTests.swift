//
//  CleanHistoryTests.swift
//  ReclaimAppCoreTests
//

import Foundation
import Testing
@testable import ReclaimAppCore

@Suite("Clean history store")
struct CleanHistoryTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "reclaim-history-\(UUID().uuidString)")
            .appending(path: "history.json")
    }

    @Test("Entries round-trip through the file")
    func roundTrip() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = CleanHistoryStore(fileURL: url)

        let entry = CleanHistoryEntry(
            date: Date(timeIntervalSince1970: 1_750_000_000),
            targetNames: ["Derived data", "npm cache"],
            itemsRemoved: 12,
            reclaimedBytes: 41_200_000_000
        )
        store.save([entry])

        let loaded = store.load()
        #expect(loaded == [entry])
    }

    @Test("A missing file reads as empty history")
    func missingFile() {
        let store = CleanHistoryStore(fileURL: temporaryURL())
        #expect(store.load().isEmpty)
    }

    @Test("A corrupt file reads as empty history, never an error")
    func corruptFile() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: url)

        let store = CleanHistoryStore(fileURL: url)
        #expect(store.load().isEmpty)
    }
}
