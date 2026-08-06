//
//  FullDiskAccessProbeTests.swift
//  ReclaimKitTests
//
//  The probe is exercised against an injected home directory, using
//  POSIX permissions to simulate TCC's read denial.
//

import Foundation
import Testing
@testable import ReclaimKit

@Suite("Full Disk Access probe")
struct FullDiskAccessProbeTests {
    private let sentinel = "~/Library/Application Support/com.apple.TCC/TCC.db"

    @Test("A readable sentinel means access is granted")
    func readableSentinel() throws {
        try withTemporaryDirectory { home in
            try makeFile(
                in: home.appending(path: "Library/Application Support/com.apple.TCC"),
                name: "TCC.db",
                byteCount: 16
            )

            let probe = FullDiskAccessProbe(sentinelPaths: [sentinel], home: home)
            #expect(probe.check() == true)
        }
    }

    @Test("An unreadable sentinel means access is denied")
    func unreadableSentinel() throws {
        try withTemporaryDirectory { home in
            let file = try makeFile(
                in: home.appending(path: "Library/Application Support/com.apple.TCC"),
                name: "TCC.db",
                byteCount: 16
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o000], ofItemAtPath: file.path
            )
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o644], ofItemAtPath: file.path
                )
            }

            let probe = FullDiskAccessProbe(sentinelPaths: [sentinel], home: home)
            #expect(probe.check() == false)
        }
    }

    @Test("A missing sentinel is indeterminate, not a denial")
    func missingSentinel() throws {
        try withTemporaryDirectory { home in
            let probe = FullDiskAccessProbe(sentinelPaths: [sentinel], home: home)
            #expect(probe.check() == nil)
        }
    }
}
