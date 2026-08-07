//
//  UpdaterModel.swift
//  Reclaim
//
//  Owns the app's Sparkle updater. Views-layer only: ReclaimKit and
//  ReclaimAppCore stay AppKit-free, and Sparkle is an AppKit framework.
//  Compiled out of SPM builds (`swift run` has no bundle to update).
//

#if canImport(Sparkle)
import Sparkle

@MainActor
final class UpdaterModel {
    static let shared = UpdaterModel()

    private let controller: SPUStandardUpdaterController

    private init() {
        // startingUpdater: true schedules background checks and shows
        // Sparkle's built-in first-run consent prompt for automatic checks.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var updater: SPUUpdater { controller.updater }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
#endif
