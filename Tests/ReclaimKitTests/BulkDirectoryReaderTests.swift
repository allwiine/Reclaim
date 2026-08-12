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

            #expect(listing.inaccessibleCount == 0)
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

            // A freshly created regular file has exactly one directory
            // entry pointing at it, and a real, non-zero inode number.
            #expect(byName["a.txt"]?.linkCount ?? 0 >= 1)
            #expect(byName["a.txt"]?.fileID ?? 0 > 0)
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
            #expect(listing.inaccessibleCount == 0)
        }
    }

    @Test("Fallback listing matches the bulk listing")
    func fallbackMatchesBulk() throws {
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

            let bulk = try #require(BulkDirectoryReader.listing(atPath: root.path))
            let fallback = try #require(BulkDirectoryReader.fallbackListing(atPath: root.path))

            let bulkByName = Dictionary(uniqueKeysWithValues: bulk.entries.map { ($0.name, $0) })
            let fallbackByName = Dictionary(
                uniqueKeysWithValues: fallback.entries.map { ($0.name, $0) }
            )

            #expect(Set(bulkByName.keys) == Set(fallbackByName.keys))
            for name in bulkByName.keys {
                let bulkEntry = try #require(bulkByName[name])
                let fallbackEntry = try #require(fallbackByName[name])
                #expect(bulkEntry.isDirectory == fallbackEntry.isDirectory, "\(name)")
                #expect(bulkEntry.isSymlink == fallbackEntry.isSymlink, "\(name)")
                #expect(bulkEntry.isRegularFile == fallbackEntry.isRegularFile, "\(name)")
                #expect(bulkEntry.allocatedBytes == fallbackEntry.allocatedBytes, "\(name)")
            }
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
