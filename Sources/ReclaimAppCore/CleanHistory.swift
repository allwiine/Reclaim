//
//  CleanHistory.swift
//  ReclaimAppCore
//
//  Persistent record of past clean passes, powering the History view
//  and the "reclaimed all time" statistics. Stored as a small JSON
//  file; the location is injectable so tests never touch real state.
//

import Foundation

/// One completed clean pass.
public struct CleanHistoryEntry: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let date: Date
    /// Names of the targets that actually had removals, display order.
    public let targetNames: [String]
    /// Files and folders disposed of across the pass.
    public let itemsRemoved: Int
    /// Space measurably freed (post-clean rescan, never assumed).
    public let reclaimedBytes: Int64

    public init(
        id: UUID = UUID(),
        date: Date,
        targetNames: [String],
        itemsRemoved: Int,
        reclaimedBytes: Int64
    ) {
        self.id = id
        self.date = date
        self.targetNames = targetNames
        self.itemsRemoved = itemsRemoved
        self.reclaimedBytes = reclaimedBytes
    }
}

/// Loads and saves the history file. Synchronous by design — the file
/// is tiny — but calls happen off the main actor via `AppModel`.
public struct CleanHistoryStore: Sendable {
    public let fileURL: URL

    /// `~/Library/Application Support/Reclaim/history.json`.
    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Reclaim", directoryHint: .isDirectory)
            .appending(path: "history.json")
    }

    public init(fileURL: URL = Self.defaultFileURL) {
        self.fileURL = fileURL
    }

    /// Stored entries, oldest first. A missing or corrupt file reads
    /// as empty history — never an error surfaced to the UI.
    public func load() -> [CleanHistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([CleanHistoryEntry].self, from: data)) ?? []
    }

    public func save(_ entries: [CleanHistoryEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
