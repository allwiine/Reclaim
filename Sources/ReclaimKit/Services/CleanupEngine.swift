//
//  CleanupEngine.swift
//  ReclaimKit
//
//  Executes a target's CleanupStrategy. File operations sit behind a
//  protocol so the engine is unit-testable without touching the real
//  Trash, and so "move to Trash" vs "delete" is a single switch.
//

import Foundation
import os
import Synchronization

// MARK: - File operations abstraction

/// The minimal filesystem surface the engine needs.
public protocol FileRemoving: Sendable {
    /// Move an item to the user's Trash (recoverable).
    func trash(_ url: URL) throws
    /// Permanently delete an item.
    func delete(_ url: URL) throws
}

/// Production implementation backed by `FileManager`.
public struct FileManagerRemover: FileRemoving {
    public init() {}

    public func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    public func delete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

// MARK: - Outcome types

/// How removed items are disposed of. Trash is the app-wide default —
/// a storage cleaner should be forgiving of mistakes.
/// Codable so clean-history entries can record it.
public enum Disposal: String, Sendable, Codable, CaseIterable {
    case trash
    case delete
}

/// One failed path with a user-presentable reason.
public struct CleanFailure: Sendable, Equatable {
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

/// Result of cleaning one target.
public struct CleanOutcome: Sendable, Equatable {
    /// Top-level items successfully disposed of (or 1 for a successful command).
    public var removedItems: Int
    public var failures: [CleanFailure]

    public init(removedItems: Int = 0, failures: [CleanFailure] = []) {
        self.removedItems = removedItems
        self.failures = failures
    }
}

// MARK: - Engine

/// Stateless executor of cleanup strategies.
public struct CleanupEngine: Sendable {
    private let remover: any FileRemoving
    /// Hard deadline for external commands. A hung tool must not pin
    /// the clean pass forever — the UI's "stop" only takes effect
    /// between targets, so the in-flight one has to be bounded.
    private let commandTimeout: TimeInterval

    public init(
        remover: any FileRemoving = FileManagerRemover(),
        commandTimeout: TimeInterval = 10 * 60
    ) {
        self.remover = remover
        self.commandTimeout = commandTimeout
    }

    /// Clean one target. Blocking; run off the main actor.
    ///
    /// - Parameters:
    ///   - target: The registry entry being cleaned.
    ///   - cleanupPaths: The exact scan-time cleanup paths
    ///     (``TargetStatus/cleanupPaths``). The engine never lists
    ///     directories itself, so nothing created after the scan —
    ///     which the user never saw or approved — can be deleted.
    ///   - disposal: Trash (default, recoverable) or permanent delete.
    public func clean(
        _ target: CleanupTarget,
        cleanupPaths: [URL],
        disposal: Disposal
    ) -> CleanOutcome {
        var outcome = CleanOutcome()

        switch target.strategy {
        case .removeContents, .removePaths:
            // Identical here by design: the strategies differ only in
            // how the scanner derives the paths (children vs roots).
            for path in cleanupPaths {
                dispose(path, disposal: disposal, outcome: &outcome)
            }

        case .command(let spec):
            runCommand(spec, outcome: &outcome)

        case .manual(let instructions):
            // Defense in depth: the UI never offers cleaning for manual
            // targets, but if we get here anyway, refuse loudly.
            outcome.failures.append(
                CleanFailure(path: target.name, message: instructions)
            )
        }

        Log.cleaner.info(
            "Cleaned \(target.id, privacy: .public): removed \(outcome.removedItems), failures \(outcome.failures.count)"
        )
        return outcome
    }

    /// Dispose of a list of scan-time snapshot paths directly — the
    /// entry point for dev-folder artifacts, which have no registry
    /// target. Same per-item best-effort semantics as target cleaning;
    /// the engine still never lists directories itself.
    public func remove(paths: [URL], disposal: Disposal) -> CleanOutcome {
        var outcome = CleanOutcome()
        for path in paths {
            dispose(path, disposal: disposal, outcome: &outcome)
        }
        Log.cleaner.info(
            "Removed \(outcome.removedItems) artifact paths, failures \(outcome.failures.count)"
        )
        return outcome
    }

    // MARK: - Helpers

    private func dispose(_ url: URL, disposal: Disposal, outcome: inout CleanOutcome) {
        // Defense in depth: RegistryTests already forbids a catalogue
        // that reaches a structural exclusion, but the promise in
        // Settings ("never touched") is enforced here too, so no
        // future code path can dispose one by accident.
        //
        // The check runs on both the literal path and its
        // symlink-resolved form. `trashItem`/`removeItem` follow
        // *intermediate* symlink components during path resolution, so
        // a cache directory swapped for a symlink into a protected
        // location after the scan would otherwise redirect the
        // deletion. The orchestration layer additionally pins every
        // cleanup path to its scan-time real root; this is the last
        // line of defence for anything the layer above missed.
        if ExclusionRegistry.isProtected(url)
            || ExclusionRegistry.isProtected(url.resolvingSymlinksInPath()) {
            outcome.failures.append(CleanFailure(
                path: url.path,
                message: localized(
                    "engine.protectedPath",
                    defaultValue: "Protected by Reclaim's exclusion list and never removed."
                )
            ))
            return
        }
        do {
            switch disposal {
            case .trash: try remover.trash(url)
            case .delete: try remover.delete(url)
            }
            outcome.removedItems += 1
        } catch {
            outcome.failures.append(
                CleanFailure(path: url.path, message: error.localizedDescription)
            )
        }
    }

    private func runCommand(_ spec: CommandSpec, outcome: inout CleanOutcome) {
        let process = Process()
        process.executableURL = URL(filePath: spec.executablePath)
        process.arguments = spec.arguments

        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe

        // Completion is edge-triggered, not polled: the termination
        // handler signals as soon as the *direct* child exits.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            outcome.failures.append(
                CleanFailure(path: spec.displayCommand, message: error.localizedDescription)
            )
            return
        }

        // Close the parent's copy of the write end so the drain reaches
        // EOF once the child (and any process that inherited it) closes
        // it. The child kept its own dup at spawn.
        try? stderrPipe.fileHandleForWriting.close()

        // Drain stderr on a detached thread so a child that writes more
        // than the pipe buffer (~64 KB) never blocks on write. It is
        // deliberately *not* joined: a child that leaks the write end to
        // a surviving grandchild would keep this at EOF forever, and the
        // clean pass must not hang on that — we wait for the child, not
        // for the pipe. `readerFinished` lets us collect the full output
        // in the normal case without an unbounded wait in the leaked one.
        let collected = Mutex(Data())
        let readerFinished = DispatchSemaphore(value: 0)
        let readEnd = stderrPipe.fileHandleForReading
        Thread.detachNewThread {
            let data = readEnd.readDataToEndOfFile()
            collected.withLock { $0.append(data) }
            readerFinished.signal()
        }

        // Wait for the child with a hard deadline. A hung tool must not
        // pin the pass forever — the UI's Stop only takes effect between
        // targets, so the in-flight one is bounded here.
        var timedOut = false
        if exited.wait(timeout: .now() + commandTimeout) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + 5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                exited.wait()
            }
        }
        // The child is gone; in the normal case its stderr is at EOF, so
        // the reader flushes immediately. Bound the wait so a leaked
        // grandchild pipe costs at most a moment of best-effort output.
        _ = readerFinished.wait(timeout: .now() + 2)
        let stderrData = collected.withLock { $0 }

        if timedOut {
            let limit = Duration.seconds(commandTimeout)
                .formatted(.units(allowed: [.minutes, .seconds], width: .wide))
            outcome.failures.append(CleanFailure(
                path: spec.displayCommand,
                message: localized(
                    "engine.commandTimedOut",
                    defaultValue: "Stopped after \(limit) — the command never finished."
                )
            ))
        } else if process.terminationStatus == 0 {
            outcome.removedItems += 1
        } else {
            let stderrText = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Tool output is quoted verbatim (it may be in any
            // language), but framed by a localized label so mixed-
            // language failure lines read as intentional quoting.
            let message = stderrText.flatMap { $0.isEmpty ? nil : $0 }
                .map {
                    localized(
                        "engine.toolReported",
                        defaultValue: "The tool reported: “\($0)”"
                    )
                }
                ?? localized(
                    "engine.commandExitStatus",
                    defaultValue: "Exited with status \(process.terminationStatus)."
                )
            outcome.failures.append(CleanFailure(
                path: spec.displayCommand,
                message: message
            ))
        }
    }
}
