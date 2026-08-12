//
//  BulkDirectoryReaderTests.swift
//  ReclaimKitTests
//

import Foundation
import Testing
@testable import ReclaimKit

@Suite("Bulk directory reader")
struct BulkDirectoryReaderTests {
    @Test("Entries match FileManager ground truth")
    func parityWithFileManager() throws {
        try withTemporaryDirectory { root in
            try makeFile(in: root, name: "a.txt", byteCount: 5)
            try makeFile(in: root, name: ".hidden", byteCount: 3)
            try FileManager.default.createDirectory(
                at: root.appending(path: "sub"), withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(
                at: root.appending(path: "link"),
                withDestinationURL: root.appending(path: "a.txt")
            )

            let listing = try #require(BulkDirectoryReader.listing(atPath: root.path))
            let byName = Dictionary(uniqueKeysWithValues: listing.entries.map { ($0.name, $0) })

            #expect(Set(byName.keys) == ["a.txt", ".hidden", "sub", "link"])
            #expect(byName["a.txt"]?.isRegularFile == true)
            #expect(byName["sub"]?.isDirectory == true)
            #expect(byName["link"]?.isSymlink == true)
            #expect(byName["link"]?.isDirectory == false)

            // Allocated size: what FileManager reports for the same file.
            let expected = try root.appending(path: "a.txt")
                .resourceValues(forKeys: [.totalFileAllocatedSizeKey])
                .totalFileAllocatedSize
            #expect(byName["a.txt"]?.allocatedBytes == Int64(expected ?? -1))
        }
    }

    @Test("Modification dates come with the directory read")
    func modificationDates() throws {
        try withTemporaryDirectory { root in
            let file = try makeFile(in: root, name: "dated.txt", byteCount: 1)
            let expected = try file.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            let listing = try #require(BulkDirectoryReader.listing(atPath: root.path))
            let entry = try #require(listing.entries.first { $0.name == "dated.txt" })
            let date = try #require(entry.modificationDate)
            #expect(abs(date.timeIntervalSince(try #require(expected))) < 1.0)
        }
    }

    @Test("Small buffers force multiple batches without losing entries")
    func multipleBatches() throws {
        try withTemporaryDirectory { root in
            for index in 0..<300 {
                try makeFile(in: root, name: "file-\(index).txt", byteCount: 1)
            }
            let listing = try #require(
                BulkDirectoryReader.listing(atPath: root.path, bufferSize: 4096)
            )
            #expect(listing.entries.count == 300)
            #expect(Set(listing.entries.map(\.name)).count == 300)
        }
    }

    @Test("An unreadable directory yields nil")
    func unreadableDirectory() throws {
        try withTemporaryDirectory { root in
            let locked = root.appending(path: "locked")
            try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o000], ofItemAtPath: locked.path
            )
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: locked.path
                )
            }
            #expect(BulkDirectoryReader.listing(atPath: locked.path) == nil)
        }
    }

    @Test("A nonexistent path yields nil")
    func missingPath() {
        #expect(BulkDirectoryReader.listing(atPath: "/nonexistent-reclaim-fixture") == nil)
    }
}
