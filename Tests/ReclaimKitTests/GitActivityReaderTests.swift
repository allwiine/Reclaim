//
//  GitActivityReaderTests.swift
//  ReclaimKitTests
//

import Foundation
import Testing
@testable import ReclaimKit

/// Write a plausible reflog: "<old> <new> <name> <email> <epoch> <tz>\t<msg>".
private func makeReflog(inGitDirectory gitDir: URL, epochs: [Int]) throws {
    let logs = gitDir.appending(path: "logs")
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    let lines = epochs.map { epoch in
        "0000000000000000000000000000000000000000 "
            + "1111111111111111111111111111111111111111 "
            + "A Committer Name <dev@example.com> \(epoch) +0200\tcommit: fixture"
    }
    try (lines.joined(separator: "\n") + "\n")
        .write(to: logs.appending(path: "HEAD"), atomically: true, encoding: .utf8)
}

@Suite("Git activity reader")
struct GitActivityReaderTests {
    @Test("Reads the timestamp of the last reflog line")
    func lastLineWins() throws {
        try withTemporaryDirectory { root in
            let gitDir = root.appending(path: ".git")
            try makeReflog(inGitDirectory: gitDir, epochs: [1_600_000_000, 1_700_000_000])
            let date = try #require(GitActivityReader.lastActivityDate(inGitDirectory: gitDir))
            #expect(date == Date(timeIntervalSince1970: 1_700_000_000))
        }
    }

    @Test("Reads only the tail of a large reflog")
    func largeReflog() throws {
        try withTemporaryDirectory { root in
            let gitDir = root.appending(path: ".git")
            // 5000 lines ≈ 600 KB; the reader must still get the last one.
            try makeReflog(
                inGitDirectory: gitDir,
                epochs: Array(1_600_000_000..<1_600_005_000)
            )
            let date = try #require(GitActivityReader.lastActivityDate(inGitDirectory: gitDir))
            #expect(date == Date(timeIntervalSince1970: 1_600_004_999))
        }
    }

    @Test("Missing reflog yields nil")
    func missingReflog() throws {
        try withTemporaryDirectory { root in
            let gitDir = root.appending(path: ".git")
            try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
            #expect(GitActivityReader.lastActivityDate(inGitDirectory: gitDir) == nil)
        }
    }

    @Test("Garbage content yields nil, not a crash")
    func garbageContent() throws {
        try withTemporaryDirectory { root in
            let gitDir = root.appending(path: ".git")
            let logs = gitDir.appending(path: "logs")
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            try "not a reflog at all".write(
                to: logs.appending(path: "HEAD"), atomically: true, encoding: .utf8
            )
            #expect(GitActivityReader.lastActivityDate(inGitDirectory: gitDir) == nil)
        }
    }
}
