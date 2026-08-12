//
//  DiscoveredProject.swift
//  ReclaimKit
//
//  Value types for the dev-folder feature: what discovery found in the
//  user's development folders. UI-free; formatting is the app's job.
//

import Foundation

/// One regenerable artifact directory inside a project.
public struct DiscoveredArtifact: Sendable, Equatable, Identifiable {
    public let kindID: String
    public let url: URL
    /// Allocated size, measured during the same walk that found it.
    public let measurement: DiskMeasurement

    /// Stable identity: the absolute path.
    public var id: String { url.path }
    public var kind: ArtifactKind? { ArtifactCatalog.kind(withID: kindID) }

    public init(kindID: String, url: URL, measurement: DiskMeasurement) {
        self.kindID = kindID
        self.url = url
        self.measurement = measurement
    }
}

/// One project root (git repo or marker-file project) in a dev folder.
/// Projects are awareness-only — Reclaim never deletes them; only their
/// artifacts are cleanable.
public struct DiscoveredProject: Sendable, Equatable, Identifiable {
    public let url: URL
    /// The user-configured dev folder this project was found under.
    public let devRoot: URL
    public let isGitRepo: Bool
    /// Newest regular-file modification inside the project, excluding
    /// artifact interiors and `.git`.
    public let lastEditDate: Date?
    /// From the reflog tail; nil for worktree/bare layouts.
    public let lastGitActivityDate: Date?
    public var artifacts: [DiscoveredArtifact]

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    public var artifactBytes: Int64 {
        artifacts.reduce(0) { $0 + $1.measurement.bytes }
    }
    /// The later of edit and git activity — what "recently used" means.
    public var lastActivityDate: Date? {
        switch (lastEditDate, lastGitActivityDate) {
        case (let edit?, let git?): max(edit, git)
        case (let edit?, nil): edit
        case (nil, let git?): git
        case (nil, nil): nil
        }
    }

    public init(
        url: URL, devRoot: URL, isGitRepo: Bool,
        lastEditDate: Date?, lastGitActivityDate: Date?,
        artifacts: [DiscoveredArtifact]
    ) {
        self.url = url
        self.devRoot = devRoot
        self.isGitRepo = isGitRepo
        self.lastEditDate = lastEditDate
        self.lastGitActivityDate = lastGitActivityDate
        self.artifacts = artifacts
    }
}

/// The result of scanning one configured dev folder.
public struct DevRootScan: Sendable, Equatable, Identifiable {
    public let root: URL
    public var projects: [DiscoveredProject]
    /// Set when the root itself was missing or unreadable.
    public var failureMessage: String?

    public var id: String { root.path }

    public init(root: URL, projects: [DiscoveredProject], failureMessage: String? = nil) {
        self.root = root
        self.projects = projects
        self.failureMessage = failureMessage
    }
}
