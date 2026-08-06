//
//  DiskSizer.swift
//  ReclaimKit
//
//  Measures how much disk space paths actually occupy. Uses *allocated*
//  size (what deletion frees) rather than logical size, which matters
//  for sparse files and APFS clones.
//

import Foundation

/// Synchronous, cancellation-aware directory sizing.
///
/// The walk is blocking I/O by design — callers are expected to run it
/// off the main actor (AppModel dispatches it inside background tasks
/// with bounded parallelism).
public struct DiskSizer: Sendable {
    /// How many enumerated items between cooperative cancellation checks.
    private static let cancellationCheckStride = 512

    public init() {}

    /// Measure the combined footprint of several paths.
    ///
    /// - Throws: `CancellationError` if the surrounding task is cancelled.
    public func measure(_ urls: [URL]) throws -> DiskMeasurement {
        var total = DiskMeasurement.zero
        for url in urls {
            total.add(try measureOne(url))
        }
        return total
    }

    // MARK: - Implementation

    private static let sizeKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
    ]

    private func measureOne(_ url: URL) throws -> DiskMeasurement {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .zero
        }

        // Single file (e.g. Docker.raw): read its size directly.
        guard isDirectory.boolValue else {
            let values = try? url.resourceValues(forKeys: Self.sizeKeys)
            let bytes = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
            return DiskMeasurement(bytes: bytes, fileCount: 1)
        }

        // Directory: deep enumeration, skipping nothing (hidden files
        // count — they occupy space too). Unreadable entries are skipped
        // via the error handler rather than aborting the whole scan.
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(Self.sizeKeys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return .zero
        }

        var bytes: Int64 = 0
        var fileCount = 0
        var visited = 0

        for case let item as URL in enumerator {
            visited += 1
            if visited % Self.cancellationCheckStride == 0 {
                try Task.checkCancellation()
            }
            guard
                let values = try? item.resourceValues(forKeys: Self.sizeKeys),
                values.isRegularFile == true
            else { continue }
            bytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            fileCount += 1
        }

        return DiskMeasurement(bytes: bytes, fileCount: fileCount)
    }
}
