//
//  TrashService.swift
//  Reclaim
//
//  Asks Finder to empty the Trash, so the space a clean pass moved
//  there is actually released. Uses Apple events (the supported way
//  to do this); the first use prompts for Automation permission.
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

    /// Empty the Trash via Finder. Runs the Apple event off the main
    /// thread; the outcome arrives back on the main actor.
    static func emptyTrash() async -> Outcome {
        let result: Outcome = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let script = NSAppleScript(
                    source: "tell application \"Finder\" to empty trash"
                )
                var errorInfo: NSDictionary?
                script?.executeAndReturnError(&errorInfo)
                if let errorInfo,
                   let message = errorInfo[NSAppleScript.errorMessage] as? String {
                    Log.app.error("Empty Trash failed: \(message, privacy: .public)")
                    continuation.resume(returning: .failed(message: message))
                } else {
                    continuation.resume(returning: .emptied)
                }
            }
        }
        return result
    }
}
