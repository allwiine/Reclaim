//
//  GitActivityReader.swift
//  ReclaimKit
//
//  Last local git activity from the tail of `.git/logs/HEAD` — every
//  commit, checkout, pull and reset appends a reflog line, so its last
//  timestamp is an honest "last time git did anything here". Reads at
//  most the final 2 KB and never spawns a process. This is the only
//  file whose *contents* the dev-folder discovery feature ever reads.
//

import Foundation

enum GitActivityReader {
    private static let tailBytes: UInt64 = 2048

    /// The timestamp of the last reflog entry, or nil for bare repos,
    /// worktree `.git` files, or repos without a reflog. Line format:
    /// `<old-sha> <new-sha> <name> <email> <epoch> <tz>\t<message>`.
    static func lastActivityDate(inGitDirectory gitDir: URL) -> Date? {
        let logURL = gitDir.appending(path: "logs/HEAD")
        guard let handle = try? FileHandle(forReadingFrom: logURL) else { return nil }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > tailBytes ? size - tailBytes : 0
        do { try handle.seek(toOffset: start) } catch { return nil }
        guard let data = try? handle.readToEnd() else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        guard let line = text.split(separator: "\n").last(where: { !$0.isEmpty })
        else { return nil }

        // The name field may contain spaces, so take the epoch from the
        // END of the pre-tab header: ... <epoch> <tz>.
        let header = line.split(separator: "\t").first ?? line
        let fields = header.split(separator: " ")
        guard fields.count >= 2, let epoch = TimeInterval(fields[fields.count - 2])
        else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }
}
