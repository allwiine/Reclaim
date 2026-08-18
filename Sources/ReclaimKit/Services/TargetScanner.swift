//
//  TargetScanner.swift
//  ReclaimKit
//
//  The one-call scanning facade: pattern resolution + sizing → status.
//  Pure and synchronous so it is trivially testable; concurrency is the
//  app layer's concern.
//

import Foundation
import os

/// Produces a ``TargetStatus`` for a ``CleanupTarget``.
public struct TargetScanner: Sendable {
    private let resolver: PathResolver
    private let sizer: DiskSizer

    public init(resolver: PathResolver = PathResolver(), sizer: DiskSizer = DiskSizer()) {
        self.resolver = resolver
        self.sizer = sizer
    }

    /// Scan one target. Blocking; run off the main actor.
    public func scan(_ target: CleanupTarget) -> TargetStatus {
        // Command-only targets have nothing to measure up front, but
        // may declare a probe path that gates their availability.
        guard !target.pathPatterns.isEmpty else {
            if case .command(let spec) = target.strategy,
               let probe = spec.availabilityProbePattern,
               resolver.resolve(probe).isEmpty {
                return .notInstalled
            }
            return .unmeasurable
        }

        let roots = resolver.resolveAll(target.pathPatterns)
        guard !roots.isEmpty else { return .notInstalled }

        do {
            let cleanupPaths = try Self.cleanupPaths(for: target.strategy, roots: roots)
            // For removeContents the deletion set (the children) is what
            // gets measured, so the size shown is exactly what cleaning
            // this snapshot would remove. Those children are promoted to
            // measurement roots, so a single locked one must count as
            // "unreadable", not fail the whole target — the cache root's
            // own unreadability is already caught when listing it above.
            let isRemoveContents: Bool
            if case .removeContents = target.strategy { isRemoveContents = true }
            else { isRemoveContents = false }
            let measured: [URL] = isRemoveContents ? cleanupPaths : roots
            let measurement = try sizer.measure(
                measured, failOnUnreadableRoot: !isRemoveContents
            )
            Log.scanner.debug("Scanned \(target.id, privacy: .public): \(measurement.bytes) bytes in \(measurement.fileCount) files")
            return .measured(measurement, resolvedPaths: roots, cleanupPaths: cleanupPaths)
        } catch is CancellationError {
            return .idle
        } catch {
            // The id is a fixed catalogue string (public), but the error
            // description can carry a filesystem path, so keep it private.
            Log.scanner.error("Scan failed for \(target.id, privacy: .public): \(error.localizedDescription, privacy: .private)")
            return .failed(message: error.localizedDescription)
        }
    }

    /// The exact items cleaning will dispose of, captured at scan time
    /// so nothing created after the scan can ever be deleted.
    private static func cleanupPaths(
        for strategy: CleanupStrategy, roots: [URL]
    ) throws -> [URL] {
        switch strategy {
        case .removeContents:
            try roots.flatMap { root in
                try FileManager.default.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: nil, options: []
                )
                .sorted { $0.path < $1.path }
            }
        case .removePaths:
            roots
        case .command, .manual:
            // Reclaim never deletes these directly.
            []
        }
    }
}
