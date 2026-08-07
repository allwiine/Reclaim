//
//  CleanHistoryTests.swift
//  ReclaimAppCoreTests
//

import Foundation
import ReclaimKit
import Testing
@testable import ReclaimAppCore

@Suite("Clean history store")
struct CleanHistoryTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "reclaim-history-\(UUID().uuidString)")
            .appending(path: "history.json")
    }

    @Test("Entries round-trip through the file, detail fields included")
    func roundTrip() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = CleanHistoryStore(fileURL: url)

        let entry = CleanHistoryEntry(
            date: Date(timeIntervalSince1970: 1_750_000_000),
            targetNames: ["Derived data", "npm cache"],
            itemsRemoved: 12,
            reclaimedBytes: 41_200_000_000,
            items: [
                CleanedHistoryItem(
                    targetID: "xcode-derived-data", name: "Derived data",
                    bytesFreed: 38_000_000_000
                ),
                CleanedHistoryItem(
                    targetID: "xcode-unavailable-simulators", name: "Unavailable simulators",
                    bytesFreed: nil
                ),
            ],
            disposal: .trash,
            duration: 4.1,
            freeAfterBytes: 296_000_000_000,
            trashEmptiedDate: Date(timeIntervalSince1970: 1_750_003_600)
        )
        store.save([entry])

        let loaded = store.load()
        #expect(loaded == [entry])
    }

    @Test("History written by older versions still decodes")
    func legacyEntriesDecode() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // The exact shape recorded before the detail fields existed.
        let legacy = """
        [{"id":"D3E1A6F2-4C1B-4B57-9C51-0A9E33D6B002",
          "date":"2026-07-12T09:14:00Z",
          "targetNames":["Derived data"],
          "itemsRemoved":3,
          "reclaimedBytes":1000}]
        """
        try Data(legacy.utf8).write(to: url)

        let loaded = CleanHistoryStore(fileURL: url).load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.targetNames == ["Derived data"])
        #expect(loaded.first?.items == nil)
        #expect(loaded.first?.disposal == nil)
        #expect(loaded.first?.duration == nil)
        #expect(loaded.first?.freeAfterBytes == nil)
        #expect(loaded.first?.trashEmptiedDate == nil)
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
