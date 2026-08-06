//
//  CleanupStrategy.swift
//  ReclaimKit
//
//  What "clean" means for a target. Keeping this an enum (rather than
//  per-target closures) keeps the registry declarative, Sendable, and
//  trivially testable.
//

import Foundation

/// Describes how an external command is executed for command-based cleanup.
public struct CommandSpec: Sendable, Equatable {
    /// Absolute path to the executable (never resolved via `$PATH`,
    /// so behavior is deterministic regardless of the user's shell).
    public let executablePath: String
    /// Arguments passed to the executable.
    public let arguments: [String]
    /// Human-readable description shown in the UI, e.g.
    /// "Runs `xcrun simctl delete unavailable`".
    public let displayCommand: String
    /// Optional path pattern that must resolve for the command's tool
    /// to be considered installed (e.g. `~/Library/Developer/CoreSimulator`
    /// for simctl — `/usr/bin/xcrun` exists on every Mac and proves
    /// nothing). When it resolves to nothing the target scans as
    /// `.notInstalled` instead of `.unmeasurable`.
    public let availabilityProbePattern: String?

    public init(
        executablePath: String,
        arguments: [String],
        displayCommand: String,
        availabilityProbePattern: String? = nil
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.displayCommand = displayCommand
        self.availabilityProbePattern = availabilityProbePattern
    }
}

/// How a ``CleanupTarget`` is cleaned.
public enum CleanupStrategy: Sendable, Equatable {
    /// Remove the *children* of each resolved directory, keeping the
    /// directory itself. Preferred for caches: many tools expect their
    /// cache root to exist.
    case removeContents

    /// Remove each resolved path itself (file or directory).
    case removePaths

    /// Delegate to an external command that knows how to clean safely
    /// (e.g. `xcrun simctl delete unavailable`). Targets using this
    /// usually cannot be sized ahead of time.
    case command(CommandSpec)

    /// Reclaim can *measure* this item but must not delete it directly;
    /// the associated instructions tell the user which tool to use
    /// (e.g. Docker's own `docker system prune`).
    case manual(instructions: String)

    /// Whether Reclaim itself can perform the cleanup.
    public var isCleanable: Bool {
        switch self {
        case .removeContents, .removePaths, .command: true
        case .manual: false
        }
    }
}
