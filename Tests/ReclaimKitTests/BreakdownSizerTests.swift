//
//  BreakdownSizerTests.swift
//  ReclaimKitTests
//

import Foundation
import Testing
@testable import ReclaimKit

@Suite("Breakdown sizing")
struct BreakdownSizerTests {
    private func measuredStatus(cleanupPaths: [URL], resolvedPaths: [URL] = []) -> TargetStatus {
        .measured(
            DiskMeasurement(bytes: 0, fileCount: 0),
            resolvedPaths: resolvedPaths,
            cleanupPaths: cleanupPaths
        )
    }

    @Test("Items come back largest first")
    func ordering() throws {
        try withTemporaryDirectory { root in
            try makeFile(in: root.appending(path: "small"), name: "a", byteCount: 1_000)
            try makeFile(in: root.appending(path: "large"), name: "b", byteCount: 100_000)
            try makeFile(in: root.appending(path: "medium"), name: "c", byteCount: 50_000)

            let status = measuredStatus(cleanupPaths: [
                root.appending(path: "small"),
                root.appending(path: "large"),
                root.appending(path: "medium"),
            ])
            let entries = try BreakdownSizer().largestContents(of: status)

            #expect(entries.map(\.name) == ["large", "medium", "small"])
            #expect(entries[0].bytes >= 100_000)
        }
    }

    @Test("The tail beyond the limit collapses into one aggregate row")
    func aggregateTail() throws {
        try withTemporaryDirectory { root in
            for index in 0..<6 {
                try makeFile(
                    in: root.appending(path: "dir\(index)"),
                    name: "f", byteCount: (10 - index) * 10_000
                )
            }

            let status = measuredStatus(
                cleanupPaths: (0..<6).map { root.appending(path: "dir\($0)") }
            )
            let entries = try BreakdownSizer().largestContents(of: status, limit: 4)

            #expect(entries.count == 4)
            #expect(entries.last?.itemCount == 3, "6 items, limit 4 → 3 shown + 3 aggregated")
            // Assert on the locale-independent count, not the English
            // phrasing — the label is localized and this test must pass
            // on a machine whose preferred language is Norwegian.
            #expect(entries.last?.name.contains("3") == true, "aggregate label names the tail count")
            let aggregateBytes = entries.last?.bytes ?? 0
            #expect(aggregateBytes >= 3 * 10_000, "the aggregate carries the tail's combined size")
        }
    }

    @Test("Falls back to resolved paths when there are no cleanup paths")
    func resolvedFallback() throws {
        try withTemporaryDirectory { root in
            let file = try makeFile(in: root, name: "Docker.raw", byteCount: 4_096)
            let status = measuredStatus(cleanupPaths: [], resolvedPaths: [file])

            let entries = try BreakdownSizer().largestContents(of: status)

            #expect(entries.map(\.name) == ["Docker.raw"])
        }
    }

    @Test("Unreadable items are skipped, not fatal")
    func unreadableSkipped() throws {
        try withTemporaryDirectory { root in
            try makeFile(in: root.appending(path: "ok"), name: "f", byteCount: 1_000)
            let status = measuredStatus(cleanupPaths: [
                root.appending(path: "ok"),
                root.appending(path: "ghost-does-not-exist"),
            ])

            let entries = try BreakdownSizer().largestContents(of: status)

            // The missing path measures as zero rather than erroring the
            // whole breakdown; "ok" must survive at the top.
            #expect(entries.first?.name == "ok")
        }
    }

    @Test("Same-named items in different parent directories get distinct ids")
    func distinctIdsForSameName() throws {
        try withTemporaryDirectory { root in
            try makeFile(in: root.appending(path: "parentA/VisualStudio"), name: "f", byteCount: 1_000)
            try makeFile(in: root.appending(path: "parentB/VisualStudio"), name: "f", byteCount: 2_000)

            let status = measuredStatus(cleanupPaths: [
                root.appending(path: "parentA/VisualStudio"),
                root.appending(path: "parentB/VisualStudio"),
            ])
            let entries = try BreakdownSizer().largestContents(of: status)

            #expect(entries.map(\.name) == ["VisualStudio", "VisualStudio"])
            #expect(
                Set(entries.map(\.id)).count == 2,
                "same-named items from different parents must not collide on id"
            )
        }
    }
}
