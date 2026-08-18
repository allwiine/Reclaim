//
//  CleanHistory.swift
//  ReclaimAppCore
//
//  Persistent record of past clean passes, powering the History view
//  and the "reclaimed all time" statistics. Stored as a small JSON
//  file; the location is injectable so tests never touch real state.
//

import Foundation
import os
import ReclaimKit

/// One target cleaned in a pass, for the history detail pane.
public struct CleanedHistoryItem: Sendable, Equatable, Codable {
    /// Registry id — resolved against the live registry at display time
    /// for the icon, badge, path and "since then" regrowth.
    public let targetID: String
    /// Display name at record time, so the entry stays readable even if
    /// the registry renames or drops the target later.
    public let name: String
    /// Measurably freed space, or `nil` when unknown (command targets).
    public let bytesFreed: Int64?
    /// The target's measured size right after the pass — the baseline
    /// "since then" regrowth is judged against. Without it, whatever a
    /// cherry-picked clean left behind would masquerade as regrowth.
    /// `nil` when the rescan could not measure (or on older entries).
    public let bytesAfter: Int64?

    public init(targetID: String, name: String, bytesFreed: Int64?, bytesAfter: Int64? = nil) {
        self.targetID = targetID
        self.name = name
        self.bytesFreed = bytesFreed
        self.bytesAfter = bytesAfter
    }
}

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

    // Detail-pane fields, added later — all optional so history files
    // written by earlier versions still decode.

    /// Per-target results, pass order.
    public let items: [CleanedHistoryItem]?
    /// How the pass disposed of items.
    public let disposal: Disposal?
    /// Wall-clock length of the pass, including the post-clean rescans.
    public let duration: TimeInterval?
    /// Free space on the volume measured right after the pass.
    public let freeAfterBytes: Int64?
    /// When the user emptied the Trash through Reclaim afterwards, if
    /// they did. Emptying outside Reclaim is unknowable and stays `nil`.
    public var trashEmptiedDate: Date?

    public init(
        id: UUID = UUID(),
        date: Date,
        targetNames: [String],
        itemsRemoved: Int,
        reclaimedBytes: Int64,
        items: [CleanedHistoryItem]? = nil,
        disposal: Disposal? = nil,
        duration: TimeInterval? = nil,
        freeAfterBytes: Int64? = nil,
        trashEmptiedDate: Date? = nil
    ) {
        self.id = id
        self.date = date
        self.targetNames = targetNames
        self.itemsRemoved = itemsRemoved
        self.reclaimedBytes = reclaimedBytes
        self.items = items
        self.disposal = disposal
        self.duration = duration
        self.freeAfterBytes = freeAfterBytes
        self.trashEmptiedDate = trashEmptiedDate
    }
}

/// Loads and saves the history file. Synchronous by design — the file
/// is tiny. `AppModel` loads it once at init (on the main actor) and
/// saves off the main actor after each pass.
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

    /// Stored entries, newest first at rest; `AppModel` keeps them so.
    /// A missing or unreadable file reads as empty history — never an
    /// error surfaced to the UI. Decoding is per-entry lossy: one
    /// malformed record is dropped rather than discarding the whole
    /// history (which the next save would then overwrite for good).
    public func load() -> [CleanHistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let lenient = try? decoder.decode([Lenient<CleanHistoryEntry>].self, from: data) else {
            Log.history.error("Clean history is not a decodable array; ignoring it")
            return []
        }
        let entries = lenient.compactMap(\.value)
        if entries.count != lenient.count {
            Log.history.error(
                "Dropped \(lenient.count - entries.count, privacy: .public) unreadable history entries"
            )
        }
        return entries
    }

    public func save(_ entries: [CleanHistoryEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(entries)
        } catch {
            Log.history.error(
                "Failed to encode clean history: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persistence is best-effort — a full disk or a revoked
            // permission must not crash a clean pass — but a silent stop
            // hides real data loss, so record why.
            Log.history.error(
                "Failed to write clean history: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

/// Decodes to `nil` instead of throwing when the wrapped value can't be
/// decoded, so one bad element never fails the whole array.
private struct Lenient<Wrapped: Decodable>: Decodable {
    let value: Wrapped?
    init(from decoder: any Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}
