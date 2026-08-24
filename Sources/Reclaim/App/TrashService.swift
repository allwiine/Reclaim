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
    enum Outcome: Equatable, Sendable {
        case emptied
        /// The user declined the Automation permission, or Finder
        /// refused; the Trash still has the items.
        case failed(message: String)
    }

    /// How long to wait for Finder before giving up. Emptying a large
    /// Trash is legitimately slow, but a locked-file prompt or an
    /// unanswered Automation-consent dialog would otherwise never return.
    private nonisolated static let timeout: TimeInterval = 120

    /// Empty the Trash via Finder. Safe to call from the main actor.
    static func emptyTrash() async -> Outcome {
        // Run the blocking Apple-event round trip on a GCD thread, not a
        // Swift-concurrency cooperative thread, so a slow Finder can't
        // starve the pool while the spinner spins.
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking())
            }
        }
    }

    /// Off the main actor by design (see the file header): the caller
    /// hands this to a raw GCD thread, not the concurrent-executor pool.
    private nonisolated static func runBlocking() -> Outcome {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Finder\" to empty trash"]

        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe

        // Edge-triggered completion; no polling.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            Log.app.error("Empty Trash failed: \(error.localizedDescription, privacy: .public)")
            return .failed(message: error.localizedDescription)
        }

        let timedOut = exited.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                exited.wait()
            }
        }
        // osascript's stderr is tiny and the process is gone by now, so a
        // read-to-EOF completes at once and can't deadlock.
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        if timedOut {
            Log.app.error("Empty Trash timed out after \(timeout, privacy: .public)s")
            return .failed(message: localized(
                "trash.timedOut",
                defaultValue: "Finder did not respond in time, so the Trash was left as is."
            ))
        }
        if process.terminationStatus == 0 {
            return .emptied
        }
        let message = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Log.app.error("Empty Trash failed: \(message, privacy: .public)")
        return .failed(message: message.isEmpty
            ? localized("trash.unknownError", defaultValue: "Finder did not empty the Trash.")
            : message)
    }
}
