//
//  ProjectDiscovery.swift
//  ReclaimKit
//
//  Single-pass discovery of projects and regenerable artifacts under a
//  user-chosen dev folder. Strict minimal-I/O rules (see the design
//  doc): every directory is read exactly once via BulkDirectoryReader,
//  attributes arrive with the read (no per-entry stat), no file
//  contents are opened except the reflog tail, symlinks are never
//  followed, hidden directories are pruned outside project roots, and
//  the search outside projects stops at a fixed depth.
//
//  Blocking, synchronous, cancellation-aware — run off the main actor.
//

import Foundation
import os

public struct ProjectDiscovery: Sendable {
    /// How deep below a dev root the *search* for project roots goes.
    /// Project trees themselves are walked fully.
    public static let maxSearchDepth = 6
    private static let cancellationCheckStride = 512

    public init() {}

    /// Scan one dev folder. On cancellation the projects completed so
    /// far are returned; the in-flight one is dropped.
    public func scan(root rootURL: URL) -> DevRootScan {
        let root = rootURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return DevRootScan(
                root: rootURL, projects: [],
                failureMessage: localized(
                    "discovery.rootMissing",
                    defaultValue: "This folder no longer exists."
                )
            )
        }
        guard let listing = BulkDirectoryReader.listing(atPath: root.path) else {
            return DevRootScan(
                root: rootURL, projects: [],
                failureMessage: localized(
                    "discovery.rootUnreadable",
                    defaultValue: "This folder could not be read."
                )
            )
        }

        var projects: [DiscoveredProject] = []
        do {
            try search(
                directory: root, listing: listing, depth: 0,
                devRoot: rootURL, into: &projects
            )
        } catch {
            // CancellationError: keep what completed.
        }
        Log.scanner.debug("Discovered \(projects.count) projects under \(rootURL.path, privacy: .private)")
        projects.sort { $0.artifactBytes > $1.artifactBytes }
        return DevRootScan(root: rootURL, projects: projects)
    }

    // MARK: - Search phase (outside project roots)

    private func search(
        directory: URL, listing: BulkDirectoryListing, depth: Int,
        devRoot: URL, into projects: inout [DiscoveredProject]
    ) throws {
        try Task.checkCancellation()

        if isProjectRoot(listing) {
            projects.append(
                try scanProject(at: directory, listing: listing, devRoot: devRoot)
            )
            return
        }
        guard depth < Self.maxSearchDepth else { return }

        for entry in listing.entries
        where entry.isDirectory && !entry.name.hasPrefix(".") {
            let child = directory.appending(path: entry.name)
            guard let childListing = BulkDirectoryReader.listing(atPath: child.path) else {
                continue
            }
            try search(
                directory: child, listing: childListing, depth: depth + 1,
                devRoot: devRoot, into: &projects
            )
        }
    }

    /// A project root contains `.git` (directory or worktree file) or
    /// any sibling-proof marker from the artifact catalogue.
    private func isProjectRoot(_ listing: BulkDirectoryListing) -> Bool {
        let markers = ArtifactCatalog.projectMarkers
        return listing.entries.contains {
            $0.name == ".git" || markers.contains($0.name)
        }
    }

    // MARK: - Project walk (full, with pruning)

    private struct ProjectWalkState {
        var artifacts: [DiscoveredArtifact] = []
        var newestEdit: Date?
        var isGitRepo = false
        var gitActivity: Date?
        var visited = 0
    }

    private func scanProject(
        at projectURL: URL, listing: BulkDirectoryListing, devRoot: URL
    ) throws -> DiscoveredProject {
        var state = ProjectWalkState()
        // Git signal comes only from the project ROOT's own `.git` — a
        // nested/vendored repo anywhere below must never overwrite it
        // (see walkProjectDirectory, which prunes `.git` unconditionally).
        if let gitEntry = listing.entries.first(where: { $0.name == ".git" && !$0.isSymlink }) {
            state.isGitRepo = true
            if gitEntry.isDirectory {
                state.gitActivity = GitActivityReader.lastActivityDate(
                    inGitDirectory: projectURL.appending(path: ".git")
                )
            }
            // Regular file (worktree/submodule pointer): a repo, no reflog here.
        }
        try walkProjectDirectory(projectURL, listing: listing, state: &state)
        return DiscoveredProject(
            url: projectURL,
            devRoot: devRoot,
            isGitRepo: state.isGitRepo,
            lastEditDate: state.newestEdit,
            lastGitActivityDate: state.gitActivity,
            artifacts: state.artifacts.sorted { $0.measurement.bytes > $1.measurement.bytes }
        )
    }

    private func walkProjectDirectory(
        _ directory: URL, listing: BulkDirectoryListing, state: inout ProjectWalkState
    ) throws {
        state.visited += listing.entries.count
        if state.visited >= Self.cancellationCheckStride {
            state.visited = 0
            try Task.checkCancellation()
        }
        let siblingNames = Set(listing.entries.map(\.name))

        for entry in listing.entries {
            if entry.isSymlink { continue }
            // Git signal is root-only (resolved once in scanProject); a
            // `.git` at any depth here is pruned — never descended,
            // never counted toward mtime, never written to state.
            if entry.name == ".git" { continue }

            if entry.isRegularFile {
                if let date = entry.modificationDate {
                    state.newestEdit = state.newestEdit.map { max($0, date) } ?? date
                }
                continue
            }
            guard entry.isDirectory else { continue }

            let childURL = directory.appending(path: entry.name)
            guard let kind = ArtifactCatalog.match(
                directoryName: entry.name, siblingNames: siblingNames
            ) else {
                // Ordinary project content — recurse (hidden dirs
                // included: .vscode edits are activity too).
                guard let childListing = BulkDirectoryReader.listing(atPath: childURL.path) else {
                    continue
                }
                try walkProjectDirectory(childURL, listing: childListing, state: &state)
                continue
            }

            try handleArtifactCandidate(
                kind: kind, directory: childURL, state: &state
            )
        }
    }

    /// Resolve a matched directory into an artifact (sizing it in the
    /// same pass) or, when its remaining proof fails, walk it as
    /// ordinary content — reusing the listing either way, so no
    /// directory is ever read twice.
    private func handleArtifactCandidate(
        kind: ArtifactKind, directory: URL, state: inout ProjectWalkState
    ) throws {
        guard let ownListing = BulkDirectoryReader.listing(atPath: directory.path) else {
            return
        }

        if case .contains(let marker) = kind.proof {
            guard ownListing.entries.contains(where: { $0.name == marker }) else {
                try walkProjectDirectory(directory, listing: ownListing, state: &state)
                return
            }
        }

        if let nested = kind.nestedChild {
            // e.g. Carthage → Build: the child is the artifact; the
            // rest of the matched directory is ordinary content.
            var remainder = ownListing
            remainder.entries.removeAll { $0.name == nested && $0.isDirectory }
            for entry in ownListing.entries
            where entry.name == nested && entry.isDirectory {
                let nestedURL = directory.appending(path: entry.name)
                guard let nestedListing = BulkDirectoryReader.listing(atPath: nestedURL.path)
                else { continue }
                state.artifacts.append(try makeArtifact(
                    kind: kind, url: nestedURL, listing: nestedListing
                ))
            }
            try walkProjectDirectory(directory, listing: remainder, state: &state)
            return
        }

        state.artifacts.append(try makeArtifact(
            kind: kind, url: directory, listing: ownListing
        ))
    }

    // MARK: - Sizing phase (inside artifacts)

    private struct SizingState {
        var measurement = DiskMeasurement.zero
        var seenFileIDs = Set<UInt64>()
        var visited = 0
    }

    private func makeArtifact(
        kind: ArtifactKind, url: URL, listing: BulkDirectoryListing
    ) throws -> DiscoveredArtifact {
        var sizing = SizingState()
        try size(directory: url, listing: listing, state: &sizing)
        return DiscoveredArtifact(kindID: kind.id, url: url, measurement: sizing.measurement)
    }

    private func size(
        directory: URL, listing: BulkDirectoryListing, state: inout SizingState
    ) throws {
        state.visited += listing.entries.count
        if state.visited >= Self.cancellationCheckStride {
            state.visited = 0
            try Task.checkCancellation()
        }
        state.measurement.inaccessibleItems += listing.inaccessibleCount

        for entry in listing.entries {
            if entry.isSymlink {
                // Deleting a symlink frees only the link — count, no bytes.
                state.measurement.fileCount += 1
                continue
            }
            if entry.isRegularFile {
                // Hard-linked files occupy their allocation once — but
                // only dedupe when the volume actually gave us a file id.
                // A `fileID == 0` (volume that doesn't report ATTR_CMN_FILEID)
                // would otherwise collapse every such file into one after
                // the first, badly under-counting.
                if entry.linkCount > 1, entry.fileID != 0,
                   !state.seenFileIDs.insert(entry.fileID).inserted {
                    continue
                }
                state.measurement.fileCount += 1
                state.measurement.bytes += entry.allocatedBytes
                continue
            }
            guard entry.isDirectory else { continue }
            let child = directory.appending(path: entry.name)
            guard let childListing = BulkDirectoryReader.listing(atPath: child.path) else {
                state.measurement.inaccessibleItems += 1
                continue
            }
            try size(directory: child, listing: childListing, state: &state)
        }
    }
}
