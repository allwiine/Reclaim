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
    /// Immediate children of a directory (including hidden entries).
    func childrenOfDirectory(_ url: URL) throws -> [URL]
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

    public func childrenOfDirectory(_ url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        )
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
    ///   - resolvedPaths: Concrete paths from the target's latest scan.
    ///     Passing scan-time paths (instead of re-resolving) guarantees
    ///     we only ever delete what the user saw and approved.
    ///   - disposal: Trash (default, recoverable) or permanent delete.
    public func clean(
        _ target: CleanupTarget,
        resolvedPaths: [URL],
        disposal: Disposal
    ) -> CleanOutcome {
        var outcome = CleanOutcome()

        switch target.strategy {
        case .removeContents:
            for directory in resolvedPaths {
                do {
                    for child in try remover.childrenOfDirectory(directory) {
                        dispose(child, disposal: disposal, outcome: &outcome)
                    }
                } catch {
                    outcome.failures.append(
                        CleanFailure(path: directory.path, message: error.localizedDescription)
                    )
                }
            }

        case .removePaths:
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
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                outcome.removedItems += 1
            } else {
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrText = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                outcome.failures.append(CleanFailure(
                    path: spec.displayCommand,
                    message: stderrText.flatMap { $0.isEmpty ? nil : $0 }
                        ?? "Exited with status \(process.terminationStatus)."
                ))
            }
        } catch {
            outcome.failures.append(
                CleanFailure(path: spec.displayCommand, message: error.localizedDescription)
            )
        }
    }
}
