//
//  AppModel.swift
//  ReclaimAppCore
//
//  The single observable source of truth for the UI. Owns per-target
//  scan status, selection, settings, and orchestrates background work.
//  Lives in a UI-free library target so the whole orchestration layer
//  is unit-testable; the scan/clean executors are injectable seams.
//
//  Concurrency model
//  ─────────────────
//  The model is @MainActor: every property the UI reads is main-actor
//  state. Blocking filesystem work (sizing, deleting) runs through
//  `offMain`, a `nonisolated` async helper, which — with this package's
//  settings (no NonisolatedNonsendingByDefault / no default MainActor
//  isolation) — executes on the global concurrent executor, off the
//  main thread. Scans fan out through a task group with bounded width
//  so disk I/O never saturates the cooperative thread pool.
//

import Foundation
import Observation
import ReclaimKit

@MainActor
@Observable
public final class AppModel {
    // MARK: - Seams

    /// Produces a status for one target. Blocking; called off-main.
    public typealias ScanExecutor = @Sendable (CleanupTarget) -> TargetStatus
    /// Cleans one target's scan-time paths. Blocking; called off-main.
    public typealias CleanExecutor = @Sendable (CleanupTarget, [URL], Disposal) -> CleanOutcome
    /// Sizes a measured target's individual contents. Blocking; called
    /// off-main. `nil` means the computation was cancelled.
    public typealias BreakdownExecutor = @Sendable (TargetStatus) -> [BreakdownEntry]?
    /// Scans one configured dev folder. Blocking; called off-main.
    public typealias ProjectScanExecutor = @Sendable (URL) -> DevRootScan
    /// Disposes discovered artifact paths. Blocking; called off-main.
    public typealias ArtifactCleanExecutor = @Sendable ([URL], Disposal) -> CleanOutcome

    // MARK: - Constants

    /// Maximum directory walks in flight at once. Disk-bound work gains
    /// little from more parallelism and would block cooperative threads.
    private static let maxConcurrentScans = 4

    // MARK: - Catalogue

    /// All known targets, in registry order.
    public let targets: [CleanupTarget]

    // MARK: - Session state

    /// Scan status per target id. Missing entry ⇒ `.idle`.
    public private(set) var statuses: [CleanupTarget.ID: TargetStatus] = [:]

    /// Targets the user has ticked for cleaning.
    public private(set) var selection: Set<CleanupTarget.ID> = []

    /// Cherry-picked cleanup paths per target (path → scan-time bytes
    /// from the contents breakdown). A target with an entry here is
    /// *partially* selected: cleaning disposes only these paths. A
    /// selected target without an entry cleans everything.
    public private(set) var partialSelections: [CleanupTarget.ID: [String: Int64]] = [:]

    public private(set) var isScanning = false
    public private(set) var isCleaning = false
    public private(set) var lastScan: Date?

    /// True while the pre-clean confirmation is on screen (set by the
    /// view layer). The background scan defers while it is up so it can
    /// never clear the selection the user is reviewing.
    public var isReviewingSelection = false

    /// True from the moment the user asks to stop a scan until the pass
    /// actually unwinds — drives the "Stopping…" button state.
    public private(set) var isCancellingScan = false
    /// Same, for a running clean pass.
    public private(set) var isCancellingClean = false

    /// Live progress of the running scan pass, for the scanning screen.
    public struct ScanProgress: Equatable, Sendable {
        /// Targets fully measured so far.
        public let completed: Int
        public let total: Int
        /// Name of the most recently started target.
        public let currentTargetName: String
        /// Tilde-form location being walked, or the command being probed.
        public let currentPath: String

        public var fraction: Double {
            total > 0 ? Double(completed) / Double(total) : 0
        }
    }

    /// Non-nil while a scan pass is running.
    public private(set) var scanProgress: ScanProgress?
    /// Whether the most recent scan ran to completion. `false` means it
    /// was stopped early: measurements on screen are real but partial.
    /// Meaningful only once `lastScan` is non-nil.
    public private(set) var lastScanWasComplete = true

    /// Set when a cleanup pass finishes; the UI presents it as an alert
    /// and clears it by assigning `nil`.
    public var lastCleanSummary: CleanSummary?

    /// The target currently being cleaned, for progress UI.
    public struct CleanProgress: Equatable, Sendable {
        public let targetName: String
        /// Tilde-form location being cleaned, when known.
        public let targetPath: String?
        /// 1-based position within this pass.
        public let index: Int
        public let total: Int

        /// Counts the in-flight target as underway so the bar visibly
        /// moves on the first item and reaches the end during the last.
        public var fraction: Double {
            total > 0 ? Double(index) / Double(total) : 0
        }
    }

    /// Non-nil while a clean pass is processing a target.
    public private(set) var cleanProgress: CleanProgress?

    /// Whether the process can read TCC-protected locations. Evaluated
    /// at scan time; `nil` before the first scan or when indeterminate.
    public private(set) var hasFullDiskAccess: Bool?

    /// Capacity of the volume holding the user's data, for the disk
    /// card. Refreshed around scans and cleans.
    public private(set) var volumeSpace: VolumeSpace?

    /// Past clean passes, newest first.
    public private(set) var history: [CleanHistoryEntry]

    /// Target ids the user chose to keep out of automatic selection
    /// (the post-scan preselection and "select all safe"). Ticking them
    /// manually still works. Persisted across launches.
    public private(set) var autoSelectExclusions: Set<CleanupTarget.ID>

    /// On-demand "largest contents" per target, cached per scan.
    public private(set) var breakdowns: [CleanupTarget.ID: [BreakdownEntry]] = [:]

    /// User-configured development folders (the dev-folder feature is
    /// inert until this is non-empty). Persisted.
    public private(set) var devRoots: [URL] = []

    /// Discovery results per dev root, from the most recent scan.
    public private(set) var projectScans: [DevRootScan] = []

    /// Artifact ids (absolute paths) ticked for cleaning.
    public private(set) var artifactSelection: Set<String> = []

    @ObservationIgnored
    private(set) var scanTask: Task<Void, Never>?
    @ObservationIgnored
    private(set) var cleanTask: Task<Void, Never>?
    @ObservationIgnored
    private var breakdownTasks: [CleanupTarget.ID: Task<Void, Never>] = [:]
    /// Invalidation tokens for in-flight breakdown computations. A task
    /// may only publish its result while its token is still current —
    /// a result computed for an old scan must never overwrite fresh state.
    @ObservationIgnored
    private var breakdownTokens: [CleanupTarget.ID: UUID] = [:]
    /// Chains history saves so a later write can never lose to an
    /// earlier one still in flight.
    @ObservationIgnored
    private var historyPersistTask: Task<Void, Never>?

    @ObservationIgnored
    private let scanExecutor: ScanExecutor
    @ObservationIgnored
    private let cleanExecutor: CleanExecutor
    @ObservationIgnored
    private let breakdownExecutor: BreakdownExecutor
    @ObservationIgnored
    private let projectScanExecutor: ProjectScanExecutor
    @ObservationIgnored
    private let artifactCleanExecutor: ArtifactCleanExecutor
    @ObservationIgnored
    private let fullDiskAccessProbe: @Sendable () -> Bool?
    @ObservationIgnored
    private let volumeProbe: @Sendable () -> VolumeSpace?
    @ObservationIgnored
    private let historyStore: CleanHistoryStore

    // MARK: - Persisted settings

    private let defaults: UserDefaults

    private enum DefaultsKey {
        static let disposal = "settings.disposal"
        static let showNotInstalled = "settings.showNotInstalled"
        static let showEmpty = "settings.showEmpty"
        static let preselectCaution = "settings.preselectCaution"
        static let dryRun = "settings.dryRun"
        static let weeklyScan = "settings.weeklyScan"
        static let notifyLargeReclaimable = "settings.notifyLargeReclaimable"
        static let menuBarExtra = "settings.menuBarExtra"
        static let autoSelectExclusions = "settings.autoSelectExclusions"
        static let lastScanDate = "state.lastScanDate"
        static let devRoots = "settings.devRoots"
    }

    /// Reads a Bool setting through the ObservationRegistrar so views
    /// update when it changes; `fallback` applies when never set.
    private func boolSetting<Member>(
        _ keyPath: KeyPath<AppModel, Member>, key: String, fallback: Bool
    ) -> Bool {
        access(keyPath: keyPath)
        return defaults.object(forKey: key) as? Bool ?? fallback
    }

    private func setBoolSetting<Member>(
        _ keyPath: KeyPath<AppModel, Member>, key: String, to newValue: Bool
    ) {
        // Skip no-op writes: SwiftUI bindings (e.g. MenuBarExtra's
        // isInserted) can re-assign the current value during scene
        // evaluation, and an unconditional withMutation would spin an
        // invalidate-reevaluate loop.
        guard (defaults.object(forKey: key) as? Bool) != newValue else { return }
        withMutation(keyPath: keyPath) {
            defaults.set(newValue, forKey: key)
        }
    }

    /// Trash (default) or permanent deletion. Backed by UserDefaults via
    /// the ObservationRegistrar so views update when Settings change it.
    public var disposal: Disposal {
        get {
            access(keyPath: \.disposal)
            let raw = defaults.string(forKey: DefaultsKey.disposal) ?? ""
            return Disposal(rawValue: raw) ?? .trash
        }
        set {
            guard newValue != disposal else { return }
            withMutation(keyPath: \.disposal) {
                defaults.set(newValue.rawValue, forKey: DefaultsKey.disposal)
            }
        }
    }

    /// Whether tools that were not found on this Mac stay visible.
    public var showNotInstalled: Bool {
        get { boolSetting(\.showNotInstalled, key: DefaultsKey.showNotInstalled, fallback: false) }
        set { setBoolSetting(\.showNotInstalled, key: DefaultsKey.showNotInstalled, to: newValue) }
    }

    /// Whether locations the last scan measured as empty stay visible.
    /// Off by default — a clean row disappearing is the reward.
    public var showEmpty: Bool {
        get { boolSetting(\.showEmpty, key: DefaultsKey.showEmpty, fallback: false) }
        set { setBoolSetting(\.showEmpty, key: DefaultsKey.showEmpty, to: newValue) }
    }

    /// Whether Caution-rated items join the post-scan preselection.
    /// Off by default — only Safe items come ticked after a scan.
    public var preselectCaution: Bool {
        get { boolSetting(\.preselectCaution, key: DefaultsKey.preselectCaution, fallback: false) }
        set { setBoolSetting(\.preselectCaution, key: DefaultsKey.preselectCaution, to: newValue) }
    }

    /// Report what a clean pass would remove without touching anything.
    public var dryRun: Bool {
        get { boolSetting(\.dryRun, key: DefaultsKey.dryRun, fallback: false) }
        set { setBoolSetting(\.dryRun, key: DefaultsKey.dryRun, to: newValue) }
    }

    /// Re-scan automatically once a week while Reclaim is running.
    public var weeklyScanEnabled: Bool {
        get { boolSetting(\.weeklyScanEnabled, key: DefaultsKey.weeklyScan, fallback: true) }
        set { setBoolSetting(\.weeklyScanEnabled, key: DefaultsKey.weeklyScan, to: newValue) }
    }

    /// Post a notification when a background scan finds more than
    /// ``notificationThresholdBytes`` reclaimable.
    public var notifyLargeReclaimable: Bool {
        get { boolSetting(\.notifyLargeReclaimable, key: DefaultsKey.notifyLargeReclaimable, fallback: false) }
        set { setBoolSetting(\.notifyLargeReclaimable, key: DefaultsKey.notifyLargeReclaimable, to: newValue) }
    }

    /// Whether the compact menu bar summary is shown.
    public var menuBarExtraEnabled: Bool {
        get { boolSetting(\.menuBarExtraEnabled, key: DefaultsKey.menuBarExtra, fallback: true) }
        set { setBoolSetting(\.menuBarExtraEnabled, key: DefaultsKey.menuBarExtra, to: newValue) }
    }

    /// Reclaimable size that qualifies as "worth a notification".
    public static let notificationThresholdBytes: Int64 = 25_000_000_000

    /// How often the background scan runs while the app is open.
    public static let backgroundScanInterval: TimeInterval = 7 * 24 * 3600

    // MARK: - Init

    public init(
        targets: [CleanupTarget] = TargetRegistry.all,
        defaults: UserDefaults = .standard,
        scanExecutor: @escaping ScanExecutor = { TargetScanner().scan($0) },
        cleanExecutor: @escaping CleanExecutor = {
            CleanupEngine().clean($0, resolvedPaths: $1, disposal: $2)
        },
        breakdownExecutor: @escaping BreakdownExecutor = {
            // Every entry, not a top-5-plus-aggregate: cherry-picking
            // needs each cleanup path individually; the inspector does
            // its own top-5 collapsing.
            try? BreakdownSizer().largestContents(of: $0, limit: Int.max)
        },
        projectScanExecutor: @escaping ProjectScanExecutor = {
            ProjectDiscovery().scan(root: $0)
        },
        artifactCleanExecutor: @escaping ArtifactCleanExecutor = {
            CleanupEngine().remove(paths: $0, disposal: $1)
        },
        fullDiskAccessProbe: @escaping @Sendable () -> Bool? = {
            FullDiskAccessProbe().check()
        },
        volumeProbe: @escaping @Sendable () -> VolumeSpace? = {
            VolumeSpaceProbe().measure()
        },
        historyStore: CleanHistoryStore = CleanHistoryStore()
    ) {
        self.targets = targets
        self.defaults = defaults
        self.scanExecutor = scanExecutor
        self.cleanExecutor = cleanExecutor
        self.breakdownExecutor = breakdownExecutor
        self.projectScanExecutor = projectScanExecutor
        self.artifactCleanExecutor = artifactCleanExecutor
        self.fullDiskAccessProbe = fullDiskAccessProbe
        self.volumeProbe = volumeProbe
        self.historyStore = historyStore
        self.history = historyStore.load().sorted { $0.date > $1.date }
        self.autoSelectExclusions = Set(
            defaults.stringArray(forKey: DefaultsKey.autoSelectExclusions) ?? []
        )
        self.devRoots = (defaults.stringArray(forKey: DefaultsKey.devRoots) ?? [])
            .map { URL(filePath: $0) }
        refreshVolumeSpace()
    }

    // MARK: - Derived state

    public func status(of id: CleanupTarget.ID) -> TargetStatus {
        statuses[id] ?? .idle
    }

    /// Targets shown for a category, honoring the "show not installed"
    /// and "show empty" settings once a scan has happened.
    public func visibleTargets(in category: ToolCategory) -> [CleanupTarget] {
        let all = targets.filter { $0.category == category }
        guard lastScan != nil else { return all }
        return all.filter(isVisibleAfterScan)
    }

    /// Every visible target across all categories, in registry order —
    /// what the "Review everything" browser lists.
    public var allVisibleTargets: [CleanupTarget] {
        guard lastScan != nil else { return targets }
        return targets.filter(isVisibleAfterScan)
    }

    private func isVisibleAfterScan(_ target: CleanupTarget) -> Bool {
        switch status(of: target.id) {
        case .notInstalled:
            return showNotInstalled
        case .measured(let measurement, _, _)
            where measurement.bytes == 0 && measurement.inaccessibleItems == 0:
            // Provably empty. A lower-bound zero (unreadable entries)
            // stays visible — it may not actually be empty.
            return showEmpty
        default:
            return true
        }
    }

    /// Everything measured, including manual-only items like Docker and
    /// dev-folder artifacts.
    public var totalFoundBytes: Int64 {
        targets.reduce(0) { $0 + (status(of: $1.id).bytes ?? 0) } + projectArtifactBytes
    }

    /// Only what Reclaim itself can clean, including dev-folder artifacts.
    public var cleanableBytes: Int64 {
        targets.reduce(0) { sum, target in
            guard target.strategy.isCleanable else { return sum }
            return sum + (status(of: target.id).bytes ?? 0)
        } + projectArtifactBytes
    }

    /// Bytes covered by the current selection, partial picks and
    /// selected dev-folder artifacts included.
    public var selectedBytes: Int64 {
        targets.reduce(0) { $0 + selectedBytes(of: $1) } + selectedArtifactBytes
    }

    public struct CategoryTotal: Identifiable {
        public let category: ToolCategory
        public let bytes: Int64
        public var id: ToolCategory.ID { category.id }
    }

    /// Per-category measured totals in category display order.
    /// `cleanableOnly` restricts the sum to what Reclaim itself can
    /// clean — the honest figure for anything labeled "reclaimable".
    public func categoryTotals(cleanableOnly: Bool = false) -> [CategoryTotal] {
        ToolCategory.allCases.map { category in
            let bytes = targets
                .filter { $0.category == category && (!cleanableOnly || $0.strategy.isCleanable) }
                .reduce(Int64(0)) { $0 + (status(of: $1.id).bytes ?? 0) }
            return CategoryTotal(category: category, bytes: bytes)
        }
    }

    /// Measured total for a sidebar badge, or `nil` before any scan or
    /// when nothing in the category was measured.
    public func categoryTotalBytes(_ category: ToolCategory) -> Int64? {
        guard lastScan != nil else { return nil }
        let bytes = categoryTotals().first { $0.category == category }?.bytes ?? 0
        return bytes > 0 ? bytes : nil
    }

    /// The largest measured targets, for the overview list.
    public func largestTargets(limit: Int) -> [CleanupTarget] {
        targets
            .filter { (status(of: $0.id).bytes ?? 0) > 0 }
            .sorted { (status(of: $0.id).bytes ?? 0) > (status(of: $1.id).bytes ?? 0) }
            .prefix(limit)
            .map { $0 }
    }

    /// Measured bytes of one target (0 while unmeasured).
    public func bytes(of target: CleanupTarget) -> Int64 {
        status(of: target.id).bytes ?? 0
    }

    /// What the one-click "reclaim safe space" action covers: measured,
    /// cleanable, Safe-rated bytes.
    public var safeReclaimableBytes: Int64 {
        targets.reduce(0) {
            $1.safety == .safe && $1.strategy.isCleanable ? $0 + bytes(of: $1) : $0
        }
    }

    /// Number of Safe-rated targets with something to clean.
    public var safeReclaimableCount: Int {
        targets.count { $0.safety == .safe && $0.strategy.isCleanable && bytes(of: $0) > 0 }
    }

    /// Measured bytes needing a decision first (Caution + Destructive,
    /// including tool-managed items like Docker).
    public var reviewBytes: Int64 {
        targets.reduce(0) { $1.safety == .safe ? $0 : $0 + bytes(of: $1) }
    }

    /// Number of measured targets needing a decision first.
    public var reviewCount: Int {
        targets.count { $0.safety != .safe && bytes(of: $0) > 0 }
    }

    /// Measured targets Reclaim will not delete itself — their own tool
    /// has to do it (Docker, the Go toolchain). Drives the "needs your
    /// attention" cards.
    public var manualTargets: [CleanupTarget] {
        targets.filter { !$0.strategy.isCleanable && bytes(of: $0) > 0 }
    }

    /// All-time reclaimed space across recorded cleans.
    public var reclaimedAllTimeBytes: Int64 {
        history.reduce(0) { $0 + $1.reclaimedBytes }
    }

    // MARK: - Background scanning

    /// When the next automatic scan is due, or `nil` when disabled or
    /// no scan has happened yet.
    public var nextBackgroundScanDate: Date? {
        guard weeklyScanEnabled else { return nil }
        guard let last = defaults.object(forKey: DefaultsKey.lastScanDate) as? Date else {
            return nil
        }
        return last.addingTimeInterval(Self.backgroundScanInterval)
    }

    /// Start a scan if the weekly background scan is enabled and due.
    /// Called periodically by the app layer while Reclaim is running.
    /// Defers while the confirmation sheet is up — a background scan
    /// must never clear a selection the user is actively reviewing.
    public func runBackgroundScanIfDue(now: Date = .now) {
        guard weeklyScanEnabled, !isScanning, !isCleaning, !isReviewingSelection else { return }
        guard let next = nextBackgroundScanDate else { return }
        if now >= next { scanAll() }
    }

    // MARK: - Contents breakdown

    /// Kick off (or reuse) the "largest contents" computation for a
    /// measured target. Results land in ``breakdowns``.
    public func loadBreakdown(for target: CleanupTarget) {
        guard breakdowns[target.id] == nil, breakdownTasks[target.id] == nil else { return }
        let current = status(of: target.id)
        guard case .measured = current else { return }

        let compute = breakdownExecutor
        let token = UUID()
        breakdownTokens[target.id] = token
        breakdownTasks[target.id] = Task {
            let entries = await Self.offMain { compute(current) }
            // A computation that finished just before an invalidation
            // cancelled it must not publish its (stale) result.
            guard self.breakdownTokens[target.id] == token else { return }
            if let entries {
                self.breakdowns[target.id] = entries
            }
            self.breakdownTasks[target.id] = nil
            self.breakdownTokens[target.id] = nil
        }
    }

    /// Drop cached breakdowns (statuses changed, they may be stale).
    private func invalidateBreakdowns() {
        for task in breakdownTasks.values { task.cancel() }
        breakdownTasks.removeAll()
        breakdownTokens.removeAll()
        breakdowns.removeAll()
    }

    /// Invalidate one target's breakdown (after cleaning re-measured it).
    private func invalidateBreakdown(of id: CleanupTarget.ID) {
        breakdownTasks[id]?.cancel()
        breakdownTasks[id] = nil
        breakdownTokens[id] = nil
        breakdowns[id] = nil
    }

    private func refreshVolumeSpace() {
        let probe = volumeProbe
        Task {
            self.volumeSpace = await Self.offMain { probe() }
        }
    }

    // MARK: - Dev-folder projects

    /// All discovered projects across roots, scan order.
    public var projects: [DiscoveredProject] {
        projectScans.flatMap(\.projects)
    }

    /// Measured artifact bytes across all projects.
    public var projectArtifactBytes: Int64 {
        projects.reduce(0) { $0 + $1.artifactBytes }
    }

    /// The projects with the most reclaimable artifact bytes, for the
    /// overview's Projects card. Artifact-free projects are omitted.
    public func largestProjects(limit: Int) -> [DiscoveredProject] {
        projects
            .filter { $0.artifactBytes > 0 }
            .sorted { $0.artifactBytes > $1.artifactBytes }
            .prefix(limit)
            .map { $0 }
    }

    /// One entry in the overview's "biggest single locations" list —
    /// either a registry target or a discovered project. Projects are
    /// represented whole (their artifact total), not per artifact,
    /// matching how the Projects screen presents them.
    public enum OverviewFinding: Identifiable, Sendable {
        case target(CleanupTarget, bytes: Int64)
        case project(DiscoveredProject)

        public var id: String {
            switch self {
            case .target(let target, _): "target:\(target.id)"
            case .project(let project): "project:\(project.id)"
            }
        }

        public var bytes: Int64 {
            switch self {
            case .target(_, let bytes): bytes
            case .project(let project): project.artifactBytes
            }
        }
    }

    /// The largest measured findings across registry targets and
    /// dev-folder projects, by size.
    public func largestFindings(limit: Int) -> [OverviewFinding] {
        let targetFindings: [OverviewFinding] = targets.compactMap { target in
            let bytes = status(of: target.id).bytes ?? 0
            return bytes > 0 ? .target(target, bytes: bytes) : nil
        }
        let projectFindings: [OverviewFinding] = projects
            .filter { $0.artifactBytes > 0 }
            .map { .project($0) }
        return (targetFindings + projectFindings)
            .sorted { $0.bytes > $1.bytes }
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
        guard root.path != claudeRoot.path, !root.path.hasPrefix(claudeRoot.path + "/") else {
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
        let remaining = Set(projects.flatMap(\.artifacts).map(\.id))
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

    /// Whether the artifact's checkbox is enabled.
    public func isArtifactSelectable(_ artifact: DiscoveredArtifact) -> Bool {
        !isScanning && !isCleaning && artifact.measurement.bytes > 0
    }

    public func isArtifactSelected(_ artifact: DiscoveredArtifact) -> Bool {
        artifactSelection.contains(artifact.id)
    }

    public func setArtifactSelected(_ artifact: DiscoveredArtifact, _ selected: Bool) {
        if selected, isArtifactSelectable(artifact) {
            artifactSelection.insert(artifact.id)
        } else {
            artifactSelection.remove(artifact.id)
        }
    }

    /// The selected artifacts, discovery order.
    public var selectedArtifacts: [DiscoveredArtifact] {
        projects.flatMap(\.artifacts).filter { artifactSelection.contains($0.id) }
    }

    public var selectedArtifactBytes: Int64 {
        selectedArtifacts.reduce(0) { $0 + $1.measurement.bytes }
    }

    /// Whether a clean pass has anything to do — registry targets or
    /// dev-folder artifacts. Derived from live projects (via
    /// ``selectedArtifacts``), not the raw id set, so ids left dangling
    /// by a root removed out from under the selection never count.
    public var hasCleanableSelection: Bool {
        !selection.isEmpty || !selectedArtifacts.isEmpty
    }

    // MARK: - Selection

    /// Whether the row's checkbox is enabled.
    public func isSelectable(_ target: CleanupTarget) -> Bool {
        guard target.strategy.isCleanable, !isScanning, !isCleaning else { return false }
        switch status(of: target.id) {
        case .measured(let measurement, _, _): return measurement.bytes > 0
        case .unmeasurable: return true
        default: return false
        }
    }

    public func isSelected(_ target: CleanupTarget) -> Bool {
        selection.contains(target.id)
    }

    /// The selected targets, in registry order.
    public var selectedTargets: [CleanupTarget] {
        targets.filter { selection.contains($0.id) }
    }

    /// How many targets could be ticked right now — the denominator for
    /// "N of M selected". Manual-only targets never count.
    public var selectableItemCount: Int {
        selectableItemCount(among: targets)
    }

    /// The same count restricted to a subset (one browser view's list).
    public func selectableItemCount(among candidates: [CleanupTarget]) -> Int {
        candidates.count { target in
            guard target.strategy.isCleanable else { return false }
            switch status(of: target.id) {
            case .measured(let measurement, _, _): return measurement.bytes > 0
            case .unmeasurable: return true
            default: return false
            }
        }
    }

    public func isExcludedFromAutoSelect(_ target: CleanupTarget) -> Bool {
        autoSelectExclusions.contains(target.id)
    }

    /// Keep a target out of (or return it to) automatic selection.
    /// Excluding a currently ticked target unticks it immediately.
    public func setExcludedFromAutoSelect(_ target: CleanupTarget, _ excluded: Bool) {
        if excluded {
            autoSelectExclusions.insert(target.id)
            selection.remove(target.id)
            partialSelections[target.id] = nil
        } else {
            autoSelectExclusions.remove(target.id)
        }
        defaults.set(autoSelectExclusions.sorted(), forKey: DefaultsKey.autoSelectExclusions)
    }

    /// Select (fully) or deselect a target. Either way any cherry-picked
    /// subset is discarded — this is the whole-target switch.
    public func setSelected(_ target: CleanupTarget, _ selected: Bool) {
        partialSelections[target.id] = nil
        if selected, isSelectable(target) {
            selection.insert(target.id)
        } else {
            selection.remove(target.id)
        }
    }

    /// Select every selectable target rated ``SafetyLevel/safe``,
    /// honoring the user's auto-select exclusions.
    public func selectAllSafe() {
        for target in targets where target.safety == .safe
            && isSelectable(target)
            && !autoSelectExclusions.contains(target.id) {
            selection.insert(target.id)
            partialSelections[target.id] = nil
        }
    }

    public func clearSelection() {
        selection.removeAll()
        partialSelections.removeAll()
    }

    // MARK: - Cherry-picking

    public func isPartiallySelected(_ target: CleanupTarget) -> Bool {
        partialSelections[target.id] != nil
    }

    /// (ticked, total) cleanup-path counts, when partially selected.
    public func partialSelectionCounts(of target: CleanupTarget) -> (selected: Int, total: Int)? {
        guard let partial = partialSelections[target.id] else { return nil }
        return (partial.count, status(of: target.id).cleanupPaths.count)
    }

    /// Whether one scan-time cleanup path is in the effective clean scope.
    public func isPathSelected(_ target: CleanupTarget, path: String) -> Bool {
        guard selection.contains(target.id) else { return false }
        guard let partial = partialSelections[target.id] else { return true }
        return partial[path] != nil
    }

    /// Tick or untick a single scan-time cleanup path. Ticking the last
    /// missing path folds back into full selection; unticking the last
    /// ticked one deselects the target entirely.
    public func setPathSelected(_ target: CleanupTarget, path: String, _ on: Bool) {
        guard target.strategy.isCleanable, !isScanning, !isCleaning else { return }
        let allPaths = status(of: target.id).cleanupPaths.map(\.path)
        guard allPaths.contains(path) else { return }

        var chosen: Set<String>
        if !selection.contains(target.id) {
            chosen = []
        } else if let partial = partialSelections[target.id] {
            chosen = Set(partial.keys)
        } else {
            chosen = Set(allPaths)
        }
        if on { chosen.insert(path) } else { chosen.remove(path) }

        if chosen.isEmpty {
            selection.remove(target.id)
            partialSelections[target.id] = nil
        } else if chosen.count == allPaths.count {
            guard isSelectable(target) else { return }
            selection.insert(target.id)
            partialSelections[target.id] = nil
        } else {
            guard isSelectable(target) else { return }
            selection.insert(target.id)
            // Sizes come from the contents breakdown, which is loaded
            // whenever the inspector (the only place that ticks paths)
            // is showing the target.
            let entries = breakdowns[target.id] ?? []
            partialSelections[target.id] = chosen.reduce(into: [:]) { map, chosenPath in
                map[chosenPath] = entries.first { $0.id == chosenPath }?.bytes ?? 0
            }
        }
    }

    /// The exact paths a clean pass would dispose for this target now.
    public func selectedCleanupPaths(of target: CleanupTarget) -> [URL] {
        let all = status(of: target.id).cleanupPaths
        guard let partial = partialSelections[target.id] else { return all }
        return all.filter { partial.keys.contains($0.path) }
    }

    /// Bytes this target's current selection covers (subset-aware).
    public func selectedBytes(of target: CleanupTarget) -> Int64 {
        guard selection.contains(target.id) else { return 0 }
        if let partial = partialSelections[target.id] {
            return partial.values.reduce(0, +)
        }
        return status(of: target.id).bytes ?? 0
    }

    /// Scan-time size of one cleanup path, when the breakdown measured it.
    public func breakdownBytes(of target: CleanupTarget, path: String) -> Int64? {
        if let bytes = partialSelections[target.id]?[path] { return bytes }
        return breakdowns[target.id]?.first { $0.id == path }?.bytes
    }

    // MARK: - Scanning

    /// Scan every target with bounded parallelism.
    public func scanAll() {
        guard !isScanning, !isCleaning else { return }
        isScanning = true
        isCancellingScan = false
        selection.removeAll()
        partialSelections.removeAll()
        lastCleanSummary = nil
        invalidateBreakdowns()
        projectScans = []
        artifactSelection.removeAll()
        scanProgress = ScanProgress(
            completed: 0, total: targets.count + devRoots.count,
            currentTargetName: "", currentPath: ""
        )
        for target in targets {
            statuses[target.id] = .scanning
        }

        let probe = fullDiskAccessProbe
        scanTask = Task { [targets] in
            self.hasFullDiskAccess = await Self.offMain { probe() }
            await self.runScan(of: targets)
            // Any rows still marked scanning were cancelled mid-flight.
            for target in targets where self.statuses[target.id] == .scanning {
                self.statuses[target.id] = .idle
            }
            await self.runProjectScan()
            self.lastScan = .now
            self.lastScanWasComplete = !Task.isCancelled
            self.defaults.set(Date.now, forKey: DefaultsKey.lastScanDate)
            self.isScanning = false
            self.isCancellingScan = false
            self.scanProgress = nil
            self.scanTask = nil
            self.applyPostScanSelection()
            self.refreshVolumeSpace()
        }
    }

    /// Mirrors the design's post-scan behavior: Safe items come ticked
    /// (plus Caution when the setting opts in), so one click cleans.
    /// Targets the user excluded from automatic selection stay unticked.
    private func applyPostScanSelection() {
        for target in targets where isSelectable(target) {
            guard !autoSelectExclusions.contains(target.id) else { continue }
            let wanted = target.safety == .safe
                || (preselectCaution && target.safety == .caution)
            if wanted {
                selection.insert(target.id)
            }
        }
    }

    public func cancelScan() {
        guard scanTask != nil else { return }
        isCancellingScan = true
        scanTask?.cancel()
    }

    /// Stop the running clean pass after the in-flight target finishes.
    public func cancelClean() {
        guard cleanTask != nil else { return }
        isCancellingClean = true
        cleanTask?.cancel()
    }

    /// Fan out scans through a width-limited task group. Runs on the
    /// main actor; the blocking work happens inside the child tasks,
    /// which execute nonisolated on the global executor.
    private func runScan(of targets: [CleanupTarget]) async {
        let scan = scanExecutor
        await withTaskGroup(of: (CleanupTarget.ID, TargetStatus).self) { group in
            var pending = targets.makeIterator()
            var completed = 0
            // Started but not yet finished, oldest first. The head is
            // the longest-running walk — the honest thing for the
            // progress line to show while several run concurrently.
            var inFlight: [CleanupTarget] = []

            // Nested functions do not inherit the enclosing actor, so
            // spell out the isolation these need to touch progress.
            @MainActor
            func publishProgress() {
                let current = inFlight.first
                scanProgress = ScanProgress(
                    completed: completed,
                    total: targets.count + devRoots.count,
                    currentTargetName: current?.name ?? "",
                    currentPath: current.map(Self.displayLocation(of:)) ?? ""
                )
            }

            @MainActor
            @discardableResult
            func startNext() -> Bool {
                guard let target = pending.next() else { return false }
                inFlight.append(target)
                group.addTask {
                    (target.id, scan(target))
                }
                return true
            }

            for _ in 0..<Self.maxConcurrentScans {
                startNext()
            }
            publishProgress()
            while let (id, resolvedStatus) = await group.next() {
                statuses[id] = resolvedStatus
                completed += 1
                inFlight.removeAll { $0.id == id }
                startNext()
                publishProgress()
            }
        }
    }

    /// Fan dev-root discovery through the same width-limited pattern as
    /// target scans, continuing the same progress counter.
    private func runProjectScan() async {
        let roots = devRoots
        guard !roots.isEmpty, !Task.isCancelled else { return }
        let scan = projectScanExecutor
        let baseCompleted = targets.count

        await withTaskGroup(of: DevRootScan.self) { group in
            var pending = roots.makeIterator()
            var completed = 0
            var inFlight: [URL] = []

            @MainActor
            func publishProgress() {
                let current = inFlight.first
                scanProgress = ScanProgress(
                    completed: baseCompleted + completed,
                    total: targets.count + roots.count,
                    currentTargetName: current?.lastPathComponent ?? "",
                    currentPath: current.map {
                        ($0.path as NSString).abbreviatingWithTildeInPath
                    } ?? ""
                )
            }

            @MainActor
            @discardableResult
            func startNext() -> Bool {
                guard let root = pending.next() else { return false }
                inFlight.append(root)
                group.addTask { scan(root) }
                return true
            }

            for _ in 0..<Self.maxConcurrentScans {
                startNext()
            }
            publishProgress()
            while let result = await group.next() {
                // A root removed mid-scan must not resurrect: with no
                // configured root left to remove it, its rows would
                // linger until the next scan.
                if devRoots.contains(where: { $0.path == result.root.path }) {
                    projectScans.append(result)
                }
                completed += 1
                inFlight.removeAll { $0.path == result.root.path }
                startNext()
                publishProgress()
            }
        }
    }

    /// Tilde-form location shown while a target is being processed.
    private nonisolated static func displayLocation(of target: CleanupTarget) -> String {
        if let pattern = target.pathPatterns.first { return pattern }
        if case .command(let spec) = target.strategy { return spec.displayCommand }
        return target.name
    }

    // MARK: - Cleaning

    private struct CleanJob {
        let target: CleanupTarget
        let paths: [URL]
        let bytesBefore: Int64
        /// What the (possibly partial) selection is expected to free —
        /// dry-run projection only; real passes measure.
        let estimatedBytes: Int64
    }

    private struct ArtifactCleanJob {
        let artifact: DiscoveredArtifact
        let projectName: String
        let devRoot: URL
    }

    /// Clean everything currently selected — or, with `limitedTo`, only
    /// the selected targets in that set ("Clean just this"; the rest of
    /// the selection stays intact) — then re-scan the cleaned targets
    /// so the numbers on screen stay truthful.
    public func cleanSelected(limitedTo limit: Set<CleanupTarget.ID>? = nil) {
        guard !isCleaning, !isScanning else { return }
        guard !selection.isEmpty || !artifactSelection.isEmpty else { return }

        let jobs: [CleanJob] = targets.compactMap { target in
            guard selection.contains(target.id), target.strategy.isCleanable,
                  limit?.contains(target.id) != false else { return nil }
            switch status(of: target.id) {
            case .measured(let measurement, _, _):
                return CleanJob(
                    target: target,
                    paths: selectedCleanupPaths(of: target),
                    bytesBefore: measurement.bytes,
                    estimatedBytes: selectedBytes(of: target)
                )
            case .unmeasurable:
                return CleanJob(target: target, paths: [], bytesBefore: 0, estimatedBytes: 0)
            default:
                return nil
            }
        }
        // Artifact jobs join full-selection passes only — "Clean just
        // this" (limitedTo) stays a registry-target affair.
        let artifactJobs: [ArtifactCleanJob] = limit != nil ? [] : projectScans.flatMap { scan in
            scan.projects.flatMap { project in
                project.artifacts
                    .filter { artifactSelection.contains($0.id) }
                    .map { ArtifactCleanJob(
                        artifact: $0, projectName: project.name, devRoot: scan.root
                    ) }
            }
        }
        guard !jobs.isEmpty || !artifactJobs.isEmpty else { return }

        // A dry run is a report, not a pass: project the numbers from
        // the scan-time snapshot and touch nothing — no engine, no
        // rescan, and the selection stays intact.
        if dryRun {
            var summary = CleanSummary(disposal: disposal)
            summary.isDryRun = true
            for job in jobs {
                summary.itemsRemoved += max(1, job.paths.count)
                summary.cleanedTargets += 1
                summary.reclaimedBytes += job.estimatedBytes
                summary.cleaned.append(CleanSummary.CleanedTarget(
                    id: job.target.id,
                    name: job.target.name,
                    category: job.target.category,
                    // Command targets have no measurable projection.
                    bytesFreed: job.paths.isEmpty ? nil : job.estimatedBytes
                ))
            }
            for job in artifactJobs {
                summary.itemsRemoved += 1
                summary.cleanedTargets += 1
                summary.reclaimedBytes += job.artifact.measurement.bytes
                summary.cleanedArtifacts.append(CleanSummary.CleanedArtifact(
                    id: job.artifact.id,
                    name: artifactDisplayName(
                        kindID: job.artifact.kindID, projectName: job.projectName
                    ),
                    bytesFreed: job.artifact.measurement.bytes
                ))
            }
            lastCleanSummary = summary
            return
        }

        isCleaning = true
        isCancellingClean = false
        let chosenDisposal = disposal
        let scan = scanExecutor
        let clean = cleanExecutor
        let volume = volumeProbe

        cleanTask = Task {
            let passStart = Date.now
            var summary = CleanSummary(disposal: chosenDisposal)

            // Sequential on purpose: cleanup should be predictable and
            // easy to interrupt, and it is I/O-bound anyway. The
            // cancellation check sits between jobs: the in-flight
            // target always finishes, so nothing is left half-cleaned.
            for (index, job) in jobs.enumerated() {
                if Task.isCancelled {
                    summary.wasStopped = true
                    break
                }
                self.cleanProgress = CleanProgress(
                    targetName: job.target.name,
                    targetPath: job.target.pathPatterns.first,
                    index: index + 1,
                    total: jobs.count + artifactJobs.count
                )
                self.statuses[job.target.id] = .scanning

                let outcome = await Self.offMain {
                    clean(job.target, job.paths, chosenDisposal)
                }
                summary.itemsRemoved += outcome.removedItems
                if outcome.removedItems > 0 {
                    summary.cleanedTargets += 1
                } else if !outcome.failures.isEmpty {
                    summary.failedTargets += 1
                }
                summary.failures.append(contentsOf: outcome.failures.map {
                    localized(
                        "clean.failureLine",
                        defaultValue: "\(job.target.name) — \($0.message)"
                    )
                })

                let refreshed = await Self.offMain { scan(job.target) }
                self.statuses[job.target.id] = refreshed
                self.invalidateBreakdown(of: job.target.id)
                // Freed space is only claimed when the rescan could
                // measure it — command targets and failed rescans
                // report "unknown", never a guess.
                let freed = refreshed.bytes.map { max(0, job.bytesBefore - $0) }
                summary.reclaimedBytes += freed ?? 0
                if outcome.removedItems > 0 {
                    summary.cleaned.append(CleanSummary.CleanedTarget(
                        id: job.target.id,
                        name: job.target.name,
                        category: job.target.category,
                        bytesFreed: freed,
                        bytesAfter: refreshed.bytes
                    ))
                }
                self.selection.remove(job.target.id)
                self.partialSelections[job.target.id] = nil
            }

            // Dev-folder artifacts, after the registry targets. Same
            // sequential, cancellable, best-effort discipline.
            let removeArtifacts = self.artifactCleanExecutor
            var cleanedRoots: [URL] = []
            for (offset, job) in artifactJobs.enumerated() {
                if Task.isCancelled {
                    summary.wasStopped = true
                    break
                }
                let name = self.artifactDisplayName(
                    kindID: job.artifact.kindID, projectName: job.projectName
                )
                self.cleanProgress = CleanProgress(
                    targetName: name,
                    targetPath: (job.artifact.url.path as NSString).abbreviatingWithTildeInPath,
                    index: jobs.count + offset + 1,
                    total: jobs.count + artifactJobs.count
                )

                let url = job.artifact.url
                let outcome = await Self.offMain {
                    removeArtifacts([url], chosenDisposal)
                }
                summary.itemsRemoved += outcome.removedItems
                summary.failures.append(contentsOf: outcome.failures.map {
                    localized(
                        "clean.failureLine",
                        defaultValue: "\(name) — \($0.message)"
                    )
                })

                // Freed space is only claimed when the removal is
                // verifiable: the artifact is gone from disk.
                let gone = await Self.offMain {
                    !FileManager.default.fileExists(atPath: url.path)
                }
                let freed: Int64? = gone ? job.artifact.measurement.bytes : nil
                summary.reclaimedBytes += freed ?? 0
                if outcome.removedItems > 0 {
                    summary.cleanedTargets += 1
                    summary.cleanedArtifacts.append(CleanSummary.CleanedArtifact(
                        id: job.artifact.id, name: name, bytesFreed: freed
                    ))
                    if !cleanedRoots.contains(where: { $0.path == job.devRoot.path }) {
                        cleanedRoots.append(job.devRoot)
                    }
                } else if !outcome.failures.isEmpty {
                    summary.failedTargets += 1
                }
                self.artifactSelection.remove(job.artifact.id)
            }

            // Re-discover the affected roots so the Projects list stays
            // truthful — reclaimed space is measured, never assumed.
            let rescan = self.projectScanExecutor
            for root in cleanedRoots {
                let refreshed = await Self.offMain { rescan(root) }
                if let index = self.projectScans.firstIndex(where: {
                    $0.root.path == root.path
                }) {
                    self.projectScans[index] = refreshed
                }
            }

            self.cleanProgress = nil
            self.lastCleanSummary = summary
            self.isCleaning = false
            self.isCancellingClean = false
            self.cleanTask = nil
            // Volume space is measured before recording, so the entry
            // carries the honest "free after this clean" figure.
            let space = await Self.offMain { volume() }
            self.volumeSpace = space
            self.recordHistory(
                from: summary,
                duration: Date.now.timeIntervalSince(passStart),
                freeAfterBytes: space?.availableBytes
            )
        }
    }

    /// Append a real pass with removals to the persistent history.
    private func recordHistory(
        from summary: CleanSummary, duration: TimeInterval, freeAfterBytes: Int64?
    ) {
        guard !summary.isDryRun, summary.itemsRemoved > 0 else { return }
        let entry = CleanHistoryEntry(
            date: .now,
            targetNames: summary.cleaned.map(\.name) + summary.cleanedArtifacts.map(\.name),
            itemsRemoved: summary.itemsRemoved,
            reclaimedBytes: summary.reclaimedBytes,
            items: summary.cleaned.map {
                CleanedHistoryItem(
                    targetID: $0.id, name: $0.name,
                    bytesFreed: $0.bytesFreed, bytesAfter: $0.bytesAfter
                )
            } + summary.cleanedArtifacts.map {
                CleanedHistoryItem(
                    targetID: "artifact:\($0.id)", name: $0.name,
                    bytesFreed: $0.bytesFreed
                )
            },
            disposal: summary.disposal,
            duration: duration,
            freeAfterBytes: freeAfterBytes
        )
        history.insert(entry, at: 0)
        persistHistory()
    }

    /// Record that the user emptied the Trash through Reclaim. Emptying
    /// is global, so every trash-disposal pass still unmarked gets the
    /// stamp — their files all left the Trash together.
    public func markTrashEmptied(at date: Date = .now) {
        var changed = false
        for index in history.indices
        where history[index].disposal == .trash && history[index].trashEmptiedDate == nil {
            history[index].trashEmptiedDate = date
            changed = true
        }
        if changed { persistHistory() }
    }

    /// Erase the recorded clean history. Files on disk are unaffected.
    public func clearHistory() {
        history.removeAll()
        persistHistory()
    }

    /// Saves are chained so a clear issued right after a clean pass can
    /// never lose the race against the pass's own (earlier) save.
    private func persistHistory() {
        let store = historyStore
        let snapshot = history
        let previous = historyPersistTask
        historyPersistTask = Task {
            await previous?.value
            await Self.offMain { store.save(snapshot) }
        }
    }

    // MARK: - Background helpers

    /// Runs blocking work off the main actor. With this package's
    /// settings a `nonisolated` async function hops to the global
    /// concurrent executor. If `NonisolatedNonsendingByDefault` is ever
    /// enabled, annotate this `@concurrent` to preserve that behavior.
    private nonisolated static func offMain<T: Sendable>(
        _ work: @Sendable @escaping () -> T
    ) async -> T {
        work()
    }

    // MARK: - Preview support

    #if DEBUG
    /// Preview-only: install canned scan results so SwiftUI previews
    /// can render every screen without touching the filesystem.
    public func seedForPreview(
        statuses: [CleanupTarget.ID: TargetStatus],
        selection: Set<CleanupTarget.ID> = [],
        history: [CleanHistoryEntry] = [],
        breakdowns: [CleanupTarget.ID: [BreakdownEntry]] = [:],
        volumeSpace: VolumeSpace? = nil,
        hasFullDiskAccess: Bool? = true,
        lastCleanSummary: CleanSummary? = nil
    ) {
        self.statuses = statuses
        self.selection = selection
        self.history = history
        self.breakdowns = breakdowns
        self.volumeSpace = volumeSpace
        self.hasFullDiskAccess = hasFullDiskAccess
        self.lastCleanSummary = lastCleanSummary
        self.lastScan = .now
        self.lastScanWasComplete = true
    }
    #endif
}
