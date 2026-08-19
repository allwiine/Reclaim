//
//  CleanCoordinator+Pass.swift
//  ReclaimAppCore
//
//  The clean pass itself: registry targets first, then dev-folder
//  artifacts, then the re-discovery, summary, and history tail. Split
//  out of CleanCoordinator.swift for file size only — the state it reads
//  and writes is declared there.
//
//  Every disposal is pinned to the scan-time snapshot: a path whose
//  ancestry no longer resolves to its scanned root is refused, not
//  deleted, and freed space is only credited once the rescan (targets)
//  or the filesystem itself (artifacts) confirms it.
//

import Foundation
import ReclaimKit

extension CleanCoordinator {
    /// Run the pass the scope resolved to: registry targets first, then
    /// dev-folder artifacts. Sequential and cancellable between jobs, so
    /// the in-flight item always finishes and nothing is left half-done.
    func startPass(jobs: [CleanJob], artifactJobs: [ArtifactCleanJob]) {
        activity.isCleaning = true
        activity.isCancellingClean = false
        let chosenDisposal = settings.disposal
        let scan = scanExecutor
        let clean = cleanExecutor
        let volume = volumeProbe

        cleanTask = Task {
            // A clean pass must not be throttled or napped part-way — hold
            // an activity assertion for its whole duration.
            let processActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated], reason: "Cleaning reclaimable storage"
            )
            defer { ProcessInfo.processInfo.endActivity(processActivity) }
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
                self.activity.cleanProgress = CleanProgress(
                    targetName: job.target.name,
                    targetPath: job.target.pathPatterns.first,
                    index: index + 1,
                    total: jobs.count + artifactJobs.count
                )
                self.results.setStatus(.scanning, for: job.target.id)

                // Refuse any cleanup path whose ancestry no longer
                // resolves to its scan-time root — a cache directory
                // swapped for a symlink after the scan would otherwise
                // redirect deletion outside the target.
                let allowedRoots = self.results.scanRealRoots[job.target.id] ?? []
                let pathsAreChildren: Bool
                if case .removeContents = job.target.strategy {
                    pathsAreChildren = true
                } else {
                    pathsAreChildren = false
                }
                let (safePaths, refusedPaths) = await offMain {
                    Self.partitionSafe(
                        job.paths,
                        allowedRealRoots: allowedRoots,
                        pathsAreChildren: pathsAreChildren
                    )
                }
                var outcome = await offMain {
                    clean(job.target, safePaths, chosenDisposal)
                }
                for refused in refusedPaths {
                    outcome.failures.append(CleanFailure(
                        path: refused.path,
                        message: localized(
                            "clean.pathChanged",
                            defaultValue: "Its location changed since the scan, so it was left untouched."
                        )
                    ))
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

                let refreshed = await offMain { scan(job.target) }
                self.results.setStatus(refreshed, for: job.target.id)
                self.breakdowns.invalidate(job.target.id)
                // Freed space is only credited when this pass actually
                // removed something *and* the rescan could measure it.
                // A target the tool pruned itself between scan and clean
                // (or one whose disposals all failed) must not be
                // reported as space Reclaim reclaimed — command targets
                // and failed rescans report "unknown", never a guess.
                let freed = refreshed.bytes.map { max(0, job.bytesBefore - $0) }
                if outcome.removedItems > 0 {
                    summary.reclaimedBytes += freed ?? 0
                    summary.cleaned.append(CleanSummary.CleanedTarget(
                        id: job.target.id,
                        name: job.target.name,
                        category: job.target.category,
                        bytesFreed: freed,
                        bytesAfter: refreshed.bytes
                    ))
                }
                self.selection.removeAfterClean(job.target.id)
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
                let name = self.projects.artifactDisplayName(
                    kindID: job.artifact.kindID, projectName: job.projectName
                )
                self.activity.cleanProgress = CleanProgress(
                    targetName: name,
                    targetPath: (job.artifact.url.path as NSString).abbreviatingWithTildeInPath,
                    index: jobs.count + offset + 1,
                    total: jobs.count + artifactJobs.count
                )

                let url = job.artifact.url
                // Same scan-time pin as registry targets: only dispose
                // of the artifact while its parent still resolves inside
                // a scanned dev root.
                let devRootsSnapshot = self.projects.scanRealDevRoots
                let pinHolds = await offMain {
                    Self.artifactPinHolds(url, allowedRealDevRoots: devRootsSnapshot)
                }
                let outcome: CleanOutcome
                if pinHolds {
                    outcome = await offMain {
                        removeArtifacts([url], chosenDisposal)
                    }
                } else {
                    outcome = CleanOutcome(failures: [CleanFailure(
                        path: url.path,
                        message: localized(
                            "clean.pathChanged",
                            defaultValue: "Its location changed since the scan, so it was left untouched."
                        )
                    )])
                }
                summary.itemsRemoved += outcome.removedItems
                summary.failures.append(contentsOf: outcome.failures.map {
                    localized(
                        "clean.failureLine",
                        defaultValue: "\(name) — \($0.message)"
                    )
                })

                // Freed space is only credited when this pass actually
                // removed the artifact *and* it is verifiably gone from
                // disk. An artifact deleted out from under us between
                // scan and clean (a build tool, another cleaner) fails
                // the removal — its bytes are not space Reclaim freed.
                if outcome.removedItems > 0 {
                    let gone = await offMain {
                        !FileManager.default.fileExists(atPath: url.path)
                    }
                    let freed: Int64? = gone ? job.artifact.measurement.bytes : nil
                    summary.reclaimedBytes += freed ?? 0
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
                self.projects.removeFromSelection(job.artifact.id)
            }

            // Re-discover the affected roots so the Projects list stays
            // truthful — reclaimed space is measured, never assumed.
            let rescan = self.projectScanExecutor
            for root in cleanedRoots {
                let refreshed = await offMain { rescan(root) }
                self.projects.replaceScan(refreshed)
            }

            self.activity.cleanProgress = nil
            self.activity.lastCleanSummary = summary
            self.activity.isCleaning = false
            self.activity.isCancellingClean = false
            self.cleanTask = nil
            // Volume space is measured before recording, so the entry
            // carries the honest "free after this clean" figure.
            let space = await offMain { volume() }
            self.results.volumeSpace = space
            self.history.record(
                from: summary,
                duration: Date.now.timeIntervalSince(passStart),
                freeAfterBytes: space?.availableBytes
            )
        }
    }
}
