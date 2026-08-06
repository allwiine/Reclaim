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
}
