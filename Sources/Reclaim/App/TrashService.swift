//
//  TrashService.swift
//  Reclaim
//
//  Asks Finder to empty the Trash, so the space a clean pass moved
//  there is actually released. Uses Apple events (the supported way
//  to do this); the first use prompts for Automation permission.
//
//  OSA/Cocoa scripting is main-thread-only, so the script runs on the
//  main actor — a brief main-thread block while Finder empties the
//  Trash is an acceptable trade-off for correctness.
//

import AppKit
import Foundation
import os
import ReclaimKit

enum TrashService {
    enum Outcome: Equatable {
        case emptied
        /// The user declined the Automation permission, or Finder
        /// refused; the Trash still has the items.
        case failed(message: String)
    }

    /// Empty the Trash via Finder. Must run on the main actor — Apple
    /// events require it.
    @MainActor
    static func emptyTrash() -> Outcome {
        let script = NSAppleScript(
            source: "tell application \"Finder\" to empty trash"
        )
        var errorInfo: NSDictionary?
        script?.executeAndReturnError(&errorInfo)
        if let errorInfo,
           let message = errorInfo[NSAppleScript.errorMessage] as? String {
            Log.app.error("Empty Trash failed: \(message, privacy: .public)")
            return .failed(message: message)
        }
        return .emptied
    }
}
