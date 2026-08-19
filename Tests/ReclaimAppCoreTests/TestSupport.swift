//
//  TestSupport.swift
//  ReclaimAppCoreTests
//
//  Shared fixtures for the AppModel suites: stub targets, stub scan
//  results, dev-folder fixtures, and throwaway UserDefaults/history
//  stores so no test touches real app state.
//

import Foundation
import ReclaimKit
@testable import ReclaimAppCore

// MARK: - Registry target fixtures

func target(
    _ id: String,
    safety: SafetyLevel = .safe,
    strategy: CleanupStrategy = .removeContents
) -> CleanupTarget {
    CleanupTarget(
        id: id,
        name: id,
        summary: "Fixture",
        category: .otherTools,
        safety: safety,
        pathPatterns: ["~/\(id)"],
        strategy: strategy
    )
}

func commandTarget(_ id: String) -> CleanupTarget {
    CleanupTarget(
        id: id,
        name: id,
        summary: "Fixture",
        category: .otherTools,
        safety: .safe,
        pathPatterns: [],
        strategy: .command(CommandSpec(
            executablePath: "/usr/bin/true", arguments: [], displayCommand: "true"
        ))
    )
}

func measured(
    _ bytes: Int64, cleanupPaths: [URL] = [URL(filePath: "/fixture/a")]
) -> TargetStatus {
    .measured(
        DiskMeasurement(bytes: bytes, fileCount: 1),
        resolvedPaths: [URL(filePath: "/fixture")],
        cleanupPaths: cleanupPaths
    )
}

// MARK: - Dev-folder fixtures

func artifact(_ path: String, bytes: Int64) -> DiscoveredArtifact {
    DiscoveredArtifact(
        kindID: "node-modules",
        url: URL(filePath: path),
        measurement: DiskMeasurement(bytes: bytes, fileCount: 1)
    )
}

func project(
    _ path: String, devRoot: String, artifacts: [DiscoveredArtifact]
) -> DiscoveredProject {
    DiscoveredProject(
        url: URL(filePath: path), devRoot: URL(filePath: devRoot),
        isGitRepo: true, lastEditDate: nil, lastGitActivityDate: nil,
        artifacts: artifacts
    )
}

/// A fresh temporary directory, removed by the caller when done.
func makeTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "ReclaimAppCoreTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

// MARK: - Throwaway state

/// History store pointed at a throwaway file so tests never touch the
/// real Application Support state.
func temporaryHistoryStore() -> CleanHistoryStore {
    CleanHistoryStore(fileURL: FileManager.default.temporaryDirectory
        .appending(path: "reclaim-history-\(UUID().uuidString).json"))
}

/// UserDefaults suite that cleans up after itself.
final class TemporaryDefaults {
    let name = "ReclaimAppCoreTests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
    }
}
