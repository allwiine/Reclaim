//
//  ExclusionRegistry.swift
//  ReclaimKit
//
//  The catalogue's mirror image: paths Reclaim structurally refuses to
//  touch. Three consumers, one data source, no drift:
//    - SettingsView renders this list ("Excluded from scans"),
//    - RegistryTests forbids any target pattern from colliding with it,
//    - CleanupEngine refuses to dispose anything inside it at runtime.
//
//  Entries live in Catalogue/exclusions/ as JSON manifests, one file
//  per entry, bundled as a resource and loaded once by CatalogueLoader.
//  Entries are a ban list, not a scan list: a path here need not exist
//  on disk. Every entry bans three things at once — the path itself,
//  anything inside it, and any target that claims one of its ancestors
//  (disposing ~/.cargo wholesale would take credentials.toml with it).
//

import Foundation

/// A tool-family heading for the Settings presentation.
public enum ExclusionGroup: String, Sendable, CaseIterable, Identifiable {
    case claudeCode
    case aiTools
    case cloudContainers
    case toolchains
    case keysCertificates
    case editorSettings

    public var id: String { rawValue }

    /// Localized heading shown above the group's rows.
    public var displayName: String {
        switch self {
        case .claudeCode:
            localized("exclusionGroup.claudeCode.name", defaultValue: "Claude Code")
        case .aiTools:
            localized("exclusionGroup.aiTools.name", defaultValue: "AI assistants")
        case .cloudContainers:
            localized("exclusionGroup.cloudContainers.name", defaultValue: "Cloud & containers")
        case .toolchains:
            localized("exclusionGroup.toolchains.name", defaultValue: "Toolchains & registries")
        case .keysCertificates:
            localized("exclusionGroup.keysCertificates.name", defaultValue: "Keys & certificates")
        case .editorSettings:
            localized("exclusionGroup.editorSettings.name", defaultValue: "Editor settings")
        }
    }
}

/// One protected path, or a small set of sibling paths sharing a reason.
public struct StructuralExclusion: Sendable, Identifiable {
    public let id: String
    /// Tilde-form paths, no trailing slash — the same shape as
    /// `CleanupTarget.pathPatterns`, but always literal (no globs).
    public let paths: [String]
    public let group: ExclusionGroup
    /// Short localized noun phrase ("auth token", "cluster credentials").
    public let reason: String

    public init(id: String, paths: [String], group: ExclusionGroup, reason: String) {
        self.id = id
        self.paths = paths
        self.group = group
        self.reason = reason
    }
}

/// The single source of truth for structural exclusions.
public enum ExclusionRegistry {
    public static func entries(in group: ExclusionGroup) -> [StructuralExclusion] {
        all.filter { $0.group == group }
    }

    /// Absolute, tilde-expanded forms of every protected path, for the
    /// engine's runtime refusal check.
    public static let expandedProtectedPaths: [String] = all
        .flatMap(\.paths)
        .map { ($0 as NSString).expandingTildeInPath }

    /// The same paths lower-cased once, so the case-insensitive match in
    /// ``isProtected(_:)`` doesn't re-fold them on every call.
    private static let lowercasedProtectedPaths: [String] =
        expandedProtectedPaths.map { $0.lowercased() }

    /// True when `url` is a protected path, lies inside one, or is an
    /// ancestor of one (disposing an ancestor would take the protected
    /// path with it). The comparison is case-insensitive: the default
    /// APFS volume is, so `~/.SSH` must match `~/.ssh`.
    public static func isProtected(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL.path.lowercased()
        // The filesystem root is an ancestor of every exclusion.
        if candidate == "/" { return true }
        return lowercasedProtectedPaths.contains { protectedPath in
            candidate == protectedPath
                || candidate.hasPrefix(protectedPath + "/")
                || protectedPath.hasPrefix(candidate + "/")
        }
    }

    /// Roots that targets reach *into* which have been reviewed and
    /// hold nothing sensitive, so they need no exclusion entry. The
    /// reviewed-roots test in RegistryTests fails when a target reaches
    /// into a root that is neither listed here nor covered by an
    /// exclusion; adding a root here is an explicit, reviewable
    /// "nothing sensitive lives beside the targeted paths" claim.
    public static let reviewedSafeRoots: Set<String> = CatalogueLoader.bundledReviewedSafeRoots

    public static let all: [StructuralExclusion] = CatalogueLoader.bundledExclusions
}
