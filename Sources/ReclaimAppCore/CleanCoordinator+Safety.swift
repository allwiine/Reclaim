//
//  CleanCoordinator+Safety.swift
//  ReclaimAppCore
//
//  The scan-time symlink pins the clean pass consults before disposing
//  of anything. Split out of CleanCoordinator.swift for file size only.
//  Both helpers are `nonisolated static` pure functions, called through
//  the `@concurrent` workers in CleanCoordinator+Workers.swift so the
//  path resolution stays off the main thread.
//

import Foundation

extension CleanCoordinator {
    /// Split scan-time cleanup paths into those still safe to dispose
    /// and those whose ancestry changed since the scan.
    ///
    /// `allowedRealRoots` is the symlink-resolved form of the target's
    /// roots at scan time. For `.removeContents` each path is a child of
    /// a root, so its *parent* must still resolve to one of those roots;
    /// for `.removePaths` each path *is* a root. An empty set means the
    /// scan captured no pin (e.g. a command target), so the paths pass
    /// straight through to the engine's own exclusion guard.
    nonisolated static func partitionSafe(
        _ paths: [URL], allowedRealRoots: Set<String>, pathsAreChildren: Bool
    ) -> (safe: [URL], refused: [URL]) {
        guard !allowedRealRoots.isEmpty else { return (paths, []) }
        var safe: [URL] = []
        var refused: [URL] = []
        for path in paths {
            let container = pathsAreChildren ? path.deletingLastPathComponent() : path
            if allowedRealRoots.contains(container.resolvingSymlinksInPath().path) {
                safe.append(path)
            } else {
                refused.append(path)
            }
        }
        return (safe, refused)
    }

    /// True while the artifact's parent still resolves inside a scanned
    /// dev root — the same scan-time pin as ``partitionSafe(_:allowedRealRoots:pathsAreChildren:)``,
    /// for dev-folder artifacts, which have no registry root.
    nonisolated static func artifactPinHolds(
        _ url: URL, allowedRealDevRoots: Set<String>
    ) -> Bool {
        guard !allowedRealDevRoots.isEmpty else { return true }
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        return allowedRealDevRoots.contains { parent == $0 || parent.hasPrefix($0 + "/") }
    }
}
