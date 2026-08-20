//
//  AppModel+Preview.swift
//  ReclaimAppCore
//
//  Preview-only seeding: canned scan results and dev-folder discovery
//  pushed straight into the sub-models, so SwiftUI previews can render
//  every screen without touching the filesystem. DEBUG builds only.
//

import Foundation
import ReclaimKit

extension AppModel {
    // MARK: - Preview support

    #if DEBUG
    /// Preview-only: install canned scan results so SwiftUI previews
    /// can render every screen without touching the filesystem.
    public func seedForPreview(
        statuses: [CleanupTarget.ID: TargetStatus],
        selection: Set<CleanupTarget.ID> = [],
        history: [CleanHistoryEntry] = [],
        breakdowns: [CleanupTarget.ID: [BreakdownEntry]] = [:],
        volumeSpace: VolumeSpace? = nil,
        hasFullDiskAccess: Bool? = true,
        lastCleanSummary: CleanSummary? = nil
    ) {
        self.results.statuses = statuses
        self.selection.seed(ids: selection)
        self.history.seed(entries: history)
        self.breakdowns.seed(entries: breakdowns)
        self.results.volumeSpace = volumeSpace
        self.results.hasFullDiskAccess = hasFullDiskAccess
        self.activity.lastCleanSummary = lastCleanSummary
        self.results.lastScan = .now
        self.results.lastScanWasComplete = true
    }

    /// Preview-only: canned dev-folder discovery without touching
    /// UserDefaults persistence or running a scan.
    public func seedProjectsForPreview(devRoots: [URL], projectScans: [DevRootScan]) {
        projects.seed(devRoots: devRoots, projectScans: projectScans)
    }
    #endif
}
