//
//  DiskSizerTests.swift
//  ReclaimKitTests
//

import Foundation
import Testing
@testable import ReclaimKit

@Suite("Disk sizing")
struct DiskSizerTests {
    @Test("Counts files recursively and reports at least the logical size")
    func recursiveMeasurement() throws {
        try withTemporaryDirectory { root in
            try makeFile(in: root, name: "a.bin", byteCount: 1_000)
            try makeFile(in: root.appending(path: "nested"), name: "b.bin", byteCount: 2_000)
            try makeFile(in: root.appending(path: "nested/deeper"), name: "c.bin", byteCount: 3_000)

            let measurement = try DiskSizer().measure([root])

            #expect(measurement.fileCount == 3)
            // Allocated size is block-rounded, so it can exceed but never
            // undercut the logical size.
            #expect(measurement.bytes >= 6_000)
        }
    }

    @Test("A single file URL is measured directly")
    func singleFile() throws {
        try withTemporaryDirectory { root in
            let file = try makeFile(in: root, name: "big.raw", byteCount: 4_096)

            let measurement = try DiskSizer().measure([file])

            #expect(measurement.fileCount == 1)
            #expect(measurement.bytes >= 4_096)
        }
    }

    @Test("Missing paths measure as zero")
    func missingPath() throws {
        try withTemporaryDirectory { root in
            let missing = root.appending(path: "ghost")
            let measurement = try DiskSizer().measure([missing])
            #expect(measurement == .zero)
        }
    }

    @Test("Measurements accumulate across paths")
    func accumulation() throws {
        try withTemporaryDirectory { root in
            let first = root.appending(path: "one")
            let second = root.appending(path: "two")
            try makeFile(in: first, name: "a", byteCount: 100)
            try makeFile(in: second, name: "b", byteCount: 100)

            let combined = try DiskSizer().measure([first, second])

            #expect(combined.fileCount == 2)
        }
    }

    @Test("Unreadable subdirectories are skipped but counted as inaccessible")
    func inaccessibleSubdirectory() throws {
        try withTemporaryDirectory { root in
            try makeFile(in: root, name: "visible.bin", byteCount: 1_000)
            let locked = root.appending(path: "locked")
            try makeFile(in: locked, name: "hidden.bin", byteCount: 1_000)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o000], ofItemAtPath: locked.path
            )
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: locked.path
                )
            }

            let measurement = try DiskSizer().measure([root])

            #expect(measurement.fileCount == 1)
            #expect(measurement.inaccessibleItems == 1)
        }
    }

    @Test("An unreadable root throws instead of measuring zero")
    func unreadableRoot() throws {
        try withTemporaryDirectory { root in
            let locked = root.appending(path: "locked")
            try makeFile(in: locked, name: "secret.bin", byteCount: 1_000)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o000], ofItemAtPath: locked.path
            )
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: locked.path
                )
            }

            #expect(throws: (any Error).self) {
                try DiskSizer().measure([locked])
            }
        }
    }

    @Test("Hard-linked files are counted once by size")
    func hardLinkDeduplication() throws {
        try withTemporaryDirectory { root in
            let original = try makeFile(in: root, name: "original.bin", byteCount: 4_096)
            try FileManager.default.linkItem(
                at: original, to: root.appending(path: "alias.bin")
            )

            let measurement = try DiskSizer().measure([root])

            // Two directory entries, but the allocation exists once on disk.
            #expect(measurement.fileCount == 2)
            #expect(measurement.bytes < 8_192)
        }
    }
}
