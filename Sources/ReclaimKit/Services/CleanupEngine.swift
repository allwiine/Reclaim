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
public enum Disposal: String, Sendable, CaseIterable {
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

    public init(remover: any FileRemoving = FileManagerRemover()) {
        self.remover = remover
    }

    /// Clean one target. Blocking; run off the main actor.
    ///
    /// - Parameters:
    ///   - target: The registry entry being cleaned.
    ///   - resolvedPaths: The exact scan-time cleanup paths
    ///     (``TargetStatus/cleanupPaths``). The engine never lists
    ///     directories itself, so nothing created after the scan —
    ///     which the user never saw or approved — can be deleted.
    ///   - disposal: Trash (default, recoverable) or permanent delete.
    public func clean(
        _ target: CleanupTarget,
        resolvedPaths: [URL],
        disposal: Disposal
    ) -> CleanOutcome {
        var outcome = CleanOutcome()

        switch target.strategy {
        case .removeContents, .removePaths:
            // Identical here by design: the strategies differ only in
            // how the scanner derives the paths (children vs roots).
            for path in resolvedPaths {
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

    // MARK: - Helpers

    private func dispose(_ url: URL, disposal: Disposal, outcome: inout CleanOutcome) {
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

        do {
            try process.run()
            // Drain stderr to EOF *before* waiting: a child that writes
            // more than the pipe buffer (~64 KB) would otherwise block on
            // write while we block in waitUntilExit — a deadlock.
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                outcome.removedItems += 1
            } else {
                let stderrText = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                outcome.failures.append(CleanFailure(
                    path: spec.displayCommand,
                    message: stderrText.flatMap { $0.isEmpty ? nil : $0 }
                        ?? localized(
                            "engine.commandExitStatus",
                            defaultValue: "Exited with status \(process.terminationStatus)."
                        )
                ))
            }
        } catch {
            outcome.failures.append(
                CleanFailure(path: spec.displayCommand, message: error.localizedDescription)
            )
        }
    }
}
