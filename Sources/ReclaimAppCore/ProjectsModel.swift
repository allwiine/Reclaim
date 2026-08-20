//
//  ProjectsModel.swift
//  ReclaimAppCore
//
//  Dev-folder roots, discovery results, and per-project artifact totals,
//  split out of AppModel so the god class sheds its projects plumbing
//  while behavior stays identical. Artifact and project selection lives
//  in ProjectsModel+Selection.swift, which reads and writes the state
//  declared here (stored properties cannot live in an extension).
//

import Foundation
import Observation
import ReclaimKit

@Observable
public final class ProjectsModel {
    // MARK: - Session state

    /// User-configured development folders (the dev-folder feature is
    /// inert until this is non-empty). Persisted.
    public private(set) var devRoots: [URL] = []

    /// Discovery results per dev root, from the most recent scan.
    public internal(set) var projectScans: [DevRootScan] = []

    /// Artifact ids (absolute paths) ticked for cleaning.
    public internal(set) var artifactSelection: Set<String> = []

    @ObservationIgnored
    let activity: ActivityModel

    /// The same symlink pin as ``TargetResultsModel``'s scan-time roots,
    /// for dev-folder roots: an artifact is only disposed of while its
    /// parent still resolves inside a scanned dev root.
    @ObservationIgnored
    var scanRealDevRoots: Set<String> = []

    // MARK: - Persisted settings

    @ObservationIgnored
    private let defaults: UserDefaults

    private enum DefaultsKey {
        static let devRoots = "settings.devRoots"
    }

    // MARK: - Init

    public init(activity: ActivityModel, defaults: UserDefaults) {
        self.activity = activity
        self.defaults = defaults
        self.devRoots = (defaults.stringArray(forKey: DefaultsKey.devRoots) ?? [])
            .map { URL(filePath: $0) }
    }

    // MARK: - Dev-folder projects

    /// All discovered projects across roots, scan order.
    public var discovered: [DiscoveredProject] {
        projectScans.flatMap(\.projects)
    }

    /// Measured artifact bytes across all projects.
    public var projectArtifactBytes: Int64 {
        discovered.reduce(0) { $0 + $1.artifactBytes }
    }

    /// Number of projects currently holding artifact bytes — the count
    /// that pairs honestly with ``projectArtifactBytes`` in UI copy.
    public var projectsWithArtifactsCount: Int {
        discovered.count { $0.artifactBytes > 0 }
    }

    /// The projects with the most reclaimable artifact bytes, for the
    /// overview's Projects card. Artifact-free projects are omitted.
    public func largestProjects(limit: Int) -> [DiscoveredProject] {
        discovered
            .filter { $0.artifactBytes > 0 }
            .sorted { $0.artifactBytes > $1.artifactBytes }
            .prefix(limit)
            .map { $0 }
    }

    /// Add a development folder. The path is resolved (symlinks followed)
    /// before any comparison, so a symlinked root and its real target are
    /// recognized as the same root — `ProjectDiscovery` itself resolves
    /// symlinks, so project and artifact URLs always live under the
    /// resolved path. Nested roots are walked once: a folder inside an
    /// existing root is refused; a folder containing existing roots
    /// replaces them. `~/.claude` (and anything inside it) is refused
    /// outright — Claude Code's own data is structurally excluded from
    /// discovery, never a dev root.
    public func addDevRoot(_ url: URL) {
        let root = url.standardizedFileURL.resolvingSymlinksInPath()
        let claudeRoot = FileManager.default.homeDirectoryForCurrentUser
            .resolvingSymlinksInPath()
            .appending(path: ".claude")
        // Compare case-insensitively: the default APFS volume is
        // case-insensitive, so a typed `~/.CLAUDE` denotes the same
        // directory as `~/.claude` and must be refused just the same.
        let rootPath = root.path.lowercased()
        let claudePath = claudeRoot.path.lowercased()
        guard rootPath != claudePath, !rootPath.hasPrefix(claudePath + "/") else {
            return
        }
        guard !devRoots.contains(where: {
            root.path == $0.path || root.path.hasPrefix($0.path + "/")
        }) else { return }
        devRoots.removeAll { $0.path.hasPrefix(root.path + "/") }
        devRoots.append(root)
        persistDevRoots()
    }

    /// Remove a development folder and everything derived from it.
    public func removeDevRoot(_ url: URL) {
        devRoots.removeAll { $0.path == url.path }
        projectScans.removeAll { $0.root.path == url.path }
        // Prune by membership, not by path prefix: discovery resolves
        // symlinks, so artifact ids live under the *resolved* root, which
        // can differ from the configured `url` textually even though it
        // is the same root.
        let remaining = Set(discovered.flatMap(\.artifacts).map(\.id))
        artifactSelection = artifactSelection.filter { remaining.contains($0) }
        persistDevRoots()
    }

    private func persistDevRoots() {
        defaults.set(devRoots.map(\.path), forKey: DefaultsKey.devRoots)
    }

    /// Display label for an artifact: "node_modules in my-app".
    public func artifactDisplayName(kindID: String, projectName: String) -> String {
        let kindName = ArtifactCatalog.kind(withID: kindID)?.name ?? kindID
        return localized(
            "projects.artifactLabel",
            defaultValue: "\(kindName) in \(projectName)"
        )
    }

    /// Six months without edits or git activity marks a project stale
    /// (a purely visual badge — staleness changes no behavior).
    public static let staleProjectInterval: TimeInterval = 183 * 24 * 3600

    /// Whether a project shows the "no recent activity" badge. A
    /// project with no known dates is unknown, not stale.
    public func isProjectStale(_ project: DiscoveredProject, now: Date = .now) -> Bool {
        guard let activity = project.lastActivityDate else { return false }
        return now.timeIntervalSince(activity) > Self.staleProjectInterval
    }

    // MARK: - Scan seams

    /// Reset for a fresh scan: drop the previous discovery results,
    /// artifact selection, and symlink pins.
    func resetForScan() {
        projectScans = []
        artifactSelection.removeAll()
        scanRealDevRoots.removeAll()
    }

    /// Record one dev root's scan result.
    func recordScan(_ result: DevRootScan, realRoot: String) {
        // A root removed mid-scan must not resurrect: with no
        // configured root left to remove it, its rows would
        // linger until the next scan.
        if devRoots.contains(where: { $0.path == result.root.path }) {
            projectScans.append(result)
            scanRealDevRoots.insert(realRoot)
        }
    }

    /// Replace one root's discovery result — the post-clean re-scan that
    /// keeps the Projects list truthful.
    func replaceScan(_ refreshed: DevRootScan) {
        if let index = projectScans.firstIndex(where: { $0.root.path == refreshed.root.path }) {
            projectScans[index] = refreshed
        }
    }

    /// Untick one artifact, e.g. once its clean job has run.
    func removeFromSelection(_ artifactID: String) {
        artifactSelection.remove(artifactID)
    }

    // MARK: - Preview support

    #if DEBUG
    /// Preview-only: canned dev-folder discovery without touching
    /// UserDefaults persistence or running a scan.
    func seed(devRoots: [URL], projectScans: [DevRootScan]) {
        self.devRoots = devRoots
        self.projectScans = projectScans
    }
    #endif
}
