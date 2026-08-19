//
//  ActivityModel.swift
//  ReclaimAppCore
//

import Foundation
import Observation

/// What the app is doing right now — the pass flags, live progress,
/// and the latest pass outcome. Coordinators write it; every other
/// model and the UI read it. Owning these here breaks the dependency
/// cycle between selection (which must know a pass is running) and
/// the coordinators (which must know the selection).
@MainActor
@Observable
public final class ActivityModel {
    public internal(set) var isScanning = false
    public internal(set) var isCleaning = false
    /// True from the moment the user asks to stop a scan until the pass
    /// actually unwinds — drives the "Stopping…" button state.
    public internal(set) var isCancellingScan = false
    /// Same, for a running clean pass.
    public internal(set) var isCancellingClean = false
    /// True while the pre-clean confirmation is on screen (set by the
    /// view layer). The background scan defers while it is up so it can
    /// never clear the selection the user is reviewing.
    public var isReviewingSelection = false
    /// Non-nil while a scan pass is running.
    public internal(set) var scanProgress: ScanProgress?
    /// Non-nil while a clean pass is processing a target.
    public internal(set) var cleanProgress: CleanProgress?
    /// Set when a cleanup pass finishes; the UI presents it as an alert
    /// and clears it by assigning `nil`.
    public var lastCleanSummary: CleanSummary?

    public init() {}
}

/// Live progress of the running scan pass, for the scanning screen.
public struct ScanProgress: Equatable, Sendable {
    /// Targets fully measured so far.
    public let completed: Int
    public let total: Int
    /// Name of the most recently started target.
    public let currentTargetName: String
    /// Tilde-form location being walked, or the command being probed.
    public let currentPath: String

    public var fraction: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }
}

/// The target currently being cleaned, for progress UI.
public struct CleanProgress: Equatable, Sendable {
    public let targetName: String
    /// Tilde-form location being cleaned, when known.
    public let targetPath: String?
    /// 1-based position within this pass.
    public let index: Int
    public let total: Int

    /// Counts the in-flight target as underway so the bar visibly
    /// moves on the first item and reaches the end during the last.
    public var fraction: Double {
        total > 0 ? Double(index) / Double(total) : 0
    }
}
