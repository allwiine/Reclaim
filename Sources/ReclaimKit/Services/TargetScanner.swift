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
        // Command-only targets have nothing to measure up front.
        guard !target.pathPatterns.isEmpty else { return .unmeasurable }

        let paths = resolver.resolveAll(target.pathPatterns)
        guard !paths.isEmpty else { return .notInstalled }

        do {
            let measurement = try sizer.measure(paths)
            Log.scanner.debug("Scanned \(target.id, privacy: .public): \(measurement.bytes) bytes in \(measurement.fileCount) files")
            return .measured(measurement, resolvedPaths: paths)
        } catch is CancellationError {
            return .idle
        } catch {
            Log.scanner.error("Scan failed for \(target.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failed(message: error.localizedDescription)
        }
    }
}
