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
