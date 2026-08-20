//
//  ScanCoordinator+Passes.swift
//  ReclaimAppCore
//
//  The two width-limited fan-out passes a scan runs: registry targets
//  first, then dev-root discovery, sharing one progress counter. Split
//  out of ScanCoordinator.swift for file size only — the state they
//  read and write is declared there.
//

import Foundation
import ReclaimKit

extension ScanCoordinator {
    /// Fan out scans through a width-limited task group. Runs on the
    /// main actor; the blocking work happens inside the child tasks,
    /// which execute nonisolated on the global executor.
    func runScan(of targets: [CleanupTarget]) async {
        let scan = scanExecutor
        await withTaskGroup(of: (CleanupTarget.ID, TargetStatus, Set<String>).self) { group in
            var pending = targets.makeIterator()
            var completed = 0
            // Started but not yet finished, oldest first. The head is
            // the longest-running walk — the honest thing for the
            // progress line to show while several run concurrently.
            var inFlight: [CleanupTarget] = []

            // A local function declared inside a closure is nonisolated
            // even under the module's MainActor default, so these two
            // still have to spell out the isolation they touch progress
            // and start work from.
            @MainActor
            func publishProgress() {
                let current = inFlight.first
                activity.scanProgress = ScanProgress(
                    completed: completed,
                    total: targets.count + projects.devRoots.count,
                    currentTargetName: current?.name ?? "",
                    currentPath: current.map(Self.displayLocation(of:)) ?? ""
                )
            }

            @MainActor
            @discardableResult
            func startNext() -> Bool {
                guard let target = pending.next() else { return false }
                inFlight.append(target)
                group.addTask { await Self.scanWorker(scan, target) }
                return true
            }

            for _ in 0..<Self.maxConcurrentScans {
                startNext()
            }
            publishProgress()
            while let (id, resolvedStatus, realRoots) = await group.next() {
                results.setStatus(resolvedStatus, for: id)
                if realRoots.isEmpty {
                    results.scanRealRoots[id] = nil
                } else {
                    results.scanRealRoots[id] = realRoots
                }
                completed += 1
                inFlight.removeAll { $0.id == id }
                startNext()
                publishProgress()
            }
        }
    }

    /// Fan dev-root discovery through the same width-limited pattern as
    /// target scans, continuing the same progress counter.
    func runProjectScan() async {
        let roots = projects.devRoots
        guard !roots.isEmpty, !Task.isCancelled else { return }
        let scan = projectScanExecutor
        let baseCompleted = results.targets.count

        await withTaskGroup(of: (DevRootScan, String).self) { group in
            var pending = roots.makeIterator()
            var completed = 0
            var inFlight: [URL] = []

            @MainActor
            func publishProgress() {
                let current = inFlight.first
                activity.scanProgress = ScanProgress(
                    completed: baseCompleted + completed,
                    total: results.targets.count + roots.count,
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
                group.addTask { await Self.rootWorker(scan, root) }
                return true
            }

            for _ in 0..<Self.maxConcurrentScans {
                startNext()
            }
            publishProgress()
            while let (result, realRoot) = await group.next() {
                projects.recordScan(result, realRoot: realRoot)
                completed += 1
                inFlight.removeAll { $0.path == result.root.path }
                startNext()
                publishProgress()
            }
        }
    }

    // MARK: - Workers

    /// One target walk, off the main actor: the scan itself plus the
    /// scan-time resolution of the roots' real paths (the symlink pin),
    /// so cleaning can later refuse a cleanup path whose ancestry was
    /// swapped for a symlink after the scan.
    @concurrent
    private static func scanWorker(
        _ scan: ScanExecutor, _ target: CleanupTarget
    ) async -> (CleanupTarget.ID, TargetStatus, Set<String>) {
        let status = scan(target)
        let real: Set<String>
        if case .measured(_, let roots, _) = status {
            real = Set(roots.map { $0.resolvingSymlinksInPath().path })
        } else {
            real = []
        }
        return (target.id, status, real)
    }

    /// One dev-root walk, off the main actor. Resolves the root's real
    /// path in the worker so artifact cleaning can refuse anything whose
    /// parent no longer resolves inside a scanned dev root.
    @concurrent
    private static func rootWorker(
        _ scan: ProjectScanExecutor, _ root: URL
    ) async -> (DevRootScan, String) {
        (scan(root), root.resolvingSymlinksInPath().path)
    }
}
