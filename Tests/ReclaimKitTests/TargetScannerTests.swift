//
//  TargetScannerTests.swift
//  ReclaimKitTests
//
//  Status mapping of the scanning facade, against real temporary
//  directories via an injected home.
//

import Foundation
import Testing
@testable import ReclaimKit

private func makeTarget(
    patterns: [String],
    strategy: CleanupStrategy = .removeContents
) -> CleanupTarget {
    CleanupTarget(
        id: "scanner-fixture",
        name: "Scanner fixture",
        summary: "Fixture",
        category: .otherTools,
        safety: .safe,
        pathPatterns: patterns,
        strategy: strategy
    )
}

@Suite("Target scanner")
struct TargetScannerTests {
    @Test("Missing patterns produce .notInstalled")
    func notInstalled() throws {
        try withTemporaryDirectory { home in
            let scanner = TargetScanner(resolver: PathResolver(home: home))
            #expect(scanner.scan(makeTarget(patterns: ["~/nothing/here"])) == .notInstalled)
        }
    }

    @Test("Pathless command targets produce .unmeasurable")
    func unmeasurable() throws {
        let spec = CommandSpec(executablePath: "/usr/bin/true", arguments: [], displayCommand: "true")
        let scanner = TargetScanner()
        #expect(scanner.scan(makeTarget(patterns: [], strategy: .command(spec))) == .unmeasurable)
    }

    @Test("removeContents targets snapshot the directory's children at scan time")
    func removeContentsSnapshotsChildren() throws {
        try withTemporaryDirectory { home in
            let cache = home.appending(path: "cache")
            try makeFile(in: cache, name: "a.bin", byteCount: 10)
            try makeFile(in: cache, name: ".hidden", byteCount: 10)
            try FileManager.default.createDirectory(
                at: cache.appending(path: "sub"), withIntermediateDirectories: true
            )

            let scanner = TargetScanner(resolver: PathResolver(home: home))
            let status = scanner.scan(makeTarget(patterns: ["~/cache"]))

            guard case .measured(let measurement, let resolved, let cleanup) = status else {
                Issue.record("Expected .measured, got \(status)")
                return
            }
            #expect(resolved.map(\.lastPathComponent) == ["cache"])
            #expect(Set(cleanup.map(\.lastPathComponent)) == [".hidden", "a.bin", "sub"])
            #expect(measurement.fileCount == 2)
        }
    }

    @Test("removePaths targets clean the resolved roots themselves")
    func removePathsCleansRoots() throws {
        try withTemporaryDirectory { home in
            let cache = home.appending(path: "cache")
            try makeFile(in: cache, name: "a.bin", byteCount: 10)

            let scanner = TargetScanner(resolver: PathResolver(home: home))
            let status = scanner.scan(makeTarget(patterns: ["~/cache"], strategy: .removePaths))

            guard case .measured(_, let resolved, let cleanup) = status else {
                Issue.record("Expected .measured, got \(status)")
                return
            }
            #expect(cleanup == resolved)
            #expect(cleanup.map(\.lastPathComponent) == ["cache"])
        }
    }

    @Test("Manual targets are measured but expose no cleanup paths")
    func manualTargetsHaveNoCleanupPaths() throws {
        try withTemporaryDirectory { home in
            let data = home.appending(path: "data")
            try makeFile(in: data, name: "a.bin", byteCount: 10)

            let scanner = TargetScanner(resolver: PathResolver(home: home))
            let status = scanner.scan(
                makeTarget(patterns: ["~/data"], strategy: .manual(instructions: "Use the tool."))
            )

            guard case .measured(let measurement, _, let cleanup) = status else {
                Issue.record("Expected .measured, got \(status)")
                return
            }
            #expect(measurement.bytes > 0)
            #expect(cleanup.isEmpty)
        }
    }

    @Test("An unreadable target becomes .failed, not an empty measurement")
    func unreadableRootFails() throws {
        try withTemporaryDirectory { home in
            let locked = home.appending(path: "locked")
            try makeFile(in: locked, name: "secret.bin", byteCount: 1_000)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o000], ofItemAtPath: locked.path
            )
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: locked.path
                )
            }

            let scanner = TargetScanner(resolver: PathResolver(home: home))
            let status = scanner.scan(makeTarget(patterns: ["~/locked"]))

            guard case .failed = status else {
                Issue.record("Expected .failed, got \(status)")
                return
            }
        }
    }
}
