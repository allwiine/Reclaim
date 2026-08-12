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

    @Test("Tolerates multi-byte UTF-8 character at tail boundary")
    func multiByteCharacterAtBoundary() throws {
        try withTemporaryDirectory { root in
            let gitDir = root.appending(path: ".git")
            let logs = gitDir.appending(path: "logs")
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            let headURL = logs.appending(path: "HEAD")

            // Build content sized to ensure the 2048-byte tail boundary falls
            // mid-way through a multi-byte UTF-8 character. Prefix is all ASCII + multi-byte
            // chars: after an odd-length ASCII prefix, every odd position straddles a 2-byte char.
            var content = "X" // 1 byte (odd)
            content += String(repeating: "ø", count: 2100) // 4200 bytes (all 2-byte chars), starts at odd offset
            // Now content is ≈4201 bytes. When we seek to size-2048, that's position 2153.
            // Position 2153 in a stream of "Xøøøøø..." where "ø" = 0xC3 0xB8:
            // Position 0: X (1 byte, ASCII)
            // Positions 1-4200: ø chars (2 bytes each)
            // Position 2153 is odd, so it's mid-way through a ø char (continuation byte).

            // Add final valid reflog line after the padding.
            let finalEpoch = 1_700_000_000
            content += "\n0000000000000000000000000000000000000000 "
                + "1111111111111111111111111111111111111111 "
                + "A Committer <dev@example.com> \(finalEpoch) +0200\tcommit: final"

            let contentData = content.data(using: .utf8)!
            try contentData.write(to: headURL)

            // Verify the boundary actually straddles a multi-byte character.
            let data = try Data(contentsOf: headURL)
            let fileSize = UInt64(data.count)
            let tailBytes: UInt64 = 2048
            let boundaryOffset = fileSize > tailBytes ? fileSize - tailBytes : 0
            if boundaryOffset > 0 && boundaryOffset < fileSize {
                let boundaryByte = data[Int(boundaryOffset)]
                // Continuation byte has high 2 bits = 10
                let isContinuationByte = (boundaryByte & 0xC0) == 0x80
                #expect(isContinuationByte, "Boundary should fall within a multi-byte character for this test to be valid")
            }

            // Despite the boundary landing mid-character, we should still get the final line's date.
            let date = try #require(GitActivityReader.lastActivityDate(inGitDirectory: gitDir))
            #expect(date == Date(timeIntervalSince1970: TimeInterval(finalEpoch)))
        }
    }
}
