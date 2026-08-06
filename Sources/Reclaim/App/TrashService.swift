//
//  TrashService.swift
//  Reclaim
//
//  Asks Finder to empty the Trash, so the space a clean pass moved
//  there is actually released. Runs `osascript` in a child process
//  (Apple events are the supported way to do this); the first use
//  prompts for Automation permission, attributed to Reclaim as the
//  responsible process.
//
//  The Apple-event round-trip can take a while when the Trash is big,
//  so the blocking work happens off the main actor — the UI stays
//  responsive and the progress spinner actually spins.
//

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

    /// Empty the Trash via Finder. Safe to call from the main actor.
    static func emptyTrash() async -> Outcome {
        await run()
    }

    /// Off-main worker (a `nonisolated` async function hops to the
    /// global executor under this package's settings).
    private nonisolated static func run() async -> Outcome {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Finder\" to empty trash"]

        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe

        do {
            try process.run()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                return .emptied
            }
            let message = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Log.app.error("Empty Trash failed: \(message, privacy: .public)")
            return .failed(message: message.isEmpty
                ? localized("trash.unknownError", defaultValue: "Finder did not empty the Trash.")
                : message)
        } catch {
            Log.app.error("Empty Trash failed: \(error.localizedDescription, privacy: .public)")
            return .failed(message: error.localizedDescription)
        }
    }
}
