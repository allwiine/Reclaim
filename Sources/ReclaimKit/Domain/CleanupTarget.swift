//
//  CleanupTarget.swift
//  ReclaimKit
//
//  The central domain type: one value describes one cleanable location
//  (or command). The whole app is data-driven off `[CleanupTarget]` —
//  adding support for a new tool is a single entry in TargetRegistry.
//

import Foundation

/// A single cleanable item: what it is, where it lives, how risky it is
/// to clean, and how to clean it.
public struct CleanupTarget: Identifiable, Sendable {
    /// Stable, kebab-case identifier. Used for selection state and
    /// status dictionaries; must be unique across the registry
    /// (enforced by a unit test).
    public let id: String

    /// Short display name, e.g. "Derived data".
    public let name: String

    /// One or two sentences: what the data is and what happens after
    /// cleaning. Shown under the name in the list.
    public let summary: String

    public let category: ToolCategory
    public let safety: SafetyLevel

    /// Path patterns resolved at scan time. Supports:
    /// - `~` prefix → the current user's home directory
    /// - `*` glob within any single path component
    ///   (e.g. `~/Library/Caches/Google/AndroidStudio*`)
    ///
    /// Empty for command-only targets whose size cannot be measured.
    /// Patterns that don't exist on this machine are silently dropped,
    /// so a target may list several historical/candidate locations.
    public let pathPatterns: [String]

    public let strategy: CleanupStrategy

    /// Optional extra warning or tip surfaced in the row
    /// (e.g. "Prefer Claude Code's own `cleanupPeriodDays` setting.").
    public let note: String?

    public init(
        id: String,
        name: String,
        summary: String,
        category: ToolCategory,
        safety: SafetyLevel,
        pathPatterns: [String],
        strategy: CleanupStrategy,
        note: String? = nil
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.category = category
        self.safety = safety
        self.pathPatterns = pathPatterns
        self.strategy = strategy
        self.note = note
    }
}

extension CleanupTarget: Equatable, Hashable {
    /// Identity-based equality: targets are registry constants.
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
