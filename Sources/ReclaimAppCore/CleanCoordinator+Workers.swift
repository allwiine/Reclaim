//
//  CleanCoordinator+Workers.swift
//  ReclaimAppCore
//
//  The clean pass's concurrency boundary: one named `@concurrent` worker
//  per blocking step. Each does nothing but run its executor (or a pure
//  pin helper) on Sendable inputs, off the main actor — the pass in
//  CleanCoordinator+Pass.swift stays main-actor state handling.
//
//  Internal rather than private: `+Pass.swift` calls them across files.
//

import Foundation
import ReclaimKit

extension CleanCoordinator {
    /// Applies the scan-time symlink pin to a target's cleanup paths.
    @concurrent
    static func partitionWorker(
        _ paths: [URL], _ allowedRealRoots: Set<String>, _ pathsAreChildren: Bool
    ) async -> (safe: [URL], refused: [URL]) {
        partitionSafe(paths, allowedRealRoots: allowedRealRoots, pathsAreChildren: pathsAreChildren)
    }

    /// Disposes of one target's safe paths.
    @concurrent
    static func cleanWorker(
        _ clean: CleanExecutor, _ target: CleanupTarget, _ paths: [URL], _ disposal: Disposal
    ) async -> CleanOutcome {
        clean(target, paths, disposal)
    }

    /// Re-measures a target after its clean, so freed space is measured
    /// rather than assumed.
    @concurrent
    static func rescanWorker(
        _ scan: ScanExecutor, _ target: CleanupTarget
    ) async -> TargetStatus {
        scan(target)
    }

    /// Applies the scan-time symlink pin to one dev-folder artifact.
    @concurrent
    static func pinWorker(
        _ url: URL, _ allowedRealDevRoots: Set<String>
    ) async -> Bool {
        artifactPinHolds(url, allowedRealDevRoots: allowedRealDevRoots)
    }

    /// Disposes of one dev-folder artifact.
    @concurrent
    static func removeWorker(
        _ remove: ArtifactCleanExecutor, _ urls: [URL], _ disposal: Disposal
    ) async -> CleanOutcome {
        remove(urls, disposal)
    }

    /// Confirms an artifact really left the filesystem before its bytes
    /// are credited as reclaimed.
    @concurrent
    static func goneWorker(_ url: URL) async -> Bool {
        !FileManager.default.fileExists(atPath: url.path)
    }

    /// Re-discovers a cleaned dev root so the Projects list stays honest.
    @concurrent
    static func rediscoverWorker(
        _ scan: ProjectScanExecutor, _ root: URL
    ) async -> DevRootScan {
        scan(root)
    }

    /// Measures the volume once the pass has finished disposing.
    @concurrent
    static func volumeWorker(
        _ volume: @Sendable () -> VolumeSpace?
    ) async -> VolumeSpace? {
        volume()
    }
}
