//
//  Executors.swift
//  ReclaimAppCore
//
//  The injectable seams between the observable model layer and the
//  blocking filesystem work in ReclaimKit. Tests stub these; the app
//  uses the production defaults.
//

import Foundation
import ReclaimKit

/// Produces a status for one target. Blocking; called off-main.
public typealias ScanExecutor = @Sendable (CleanupTarget) -> TargetStatus
/// Cleans one target's scan-time paths. Blocking; called off-main.
public typealias CleanExecutor = @Sendable (CleanupTarget, [URL], Disposal) -> CleanOutcome
/// Sizes a measured target's individual contents. Blocking; called
/// off-main. `nil` means the computation was cancelled.
public typealias BreakdownExecutor = @Sendable (TargetStatus) -> [BreakdownEntry]?
/// Scans one configured dev folder. Blocking; called off-main.
public typealias ProjectScanExecutor = @Sendable (URL) -> DevRootScan
/// Disposes discovered artifact paths. Blocking; called off-main.
public typealias ArtifactCleanExecutor = @Sendable ([URL], Disposal) -> CleanOutcome

/// Every injectable seam, with production defaults.
public nonisolated struct Executors: Sendable {
    public var scan: ScanExecutor
    public var clean: CleanExecutor
    public var breakdown: BreakdownExecutor
    public var projectScan: ProjectScanExecutor
    public var artifactClean: ArtifactCleanExecutor
    public var fullDiskAccess: @Sendable () -> Bool?
    public var volume: @Sendable () -> VolumeSpace?

    public init(
        scan: @escaping ScanExecutor = { TargetScanner().scan($0) },
        clean: @escaping CleanExecutor = {
            CleanupEngine().clean($0, cleanupPaths: $1, disposal: $2)
        },
        breakdown: @escaping BreakdownExecutor = {
            // Every entry, not a top-5-plus-aggregate: cherry-picking
            // needs each cleanup path individually; the inspector does
            // its own top-5 collapsing.
            try? BreakdownSizer().largestContents(of: $0, limit: Int.max)
        },
        projectScan: @escaping ProjectScanExecutor = {
            ProjectDiscovery().scan(root: $0)
        },
        artifactClean: @escaping ArtifactCleanExecutor = {
            CleanupEngine().remove(paths: $0, disposal: $1)
        },
        fullDiskAccess: @escaping @Sendable () -> Bool? = {
            FullDiskAccessProbe().check()
        },
        volume: @escaping @Sendable () -> VolumeSpace? = {
            VolumeSpaceProbe().measure()
        }
    ) {
        self.scan = scan
        self.clean = clean
        self.breakdown = breakdown
        self.projectScan = projectScan
        self.artifactClean = artifactClean
        self.fullDiskAccess = fullDiskAccess
        self.volume = volume
    }
}
