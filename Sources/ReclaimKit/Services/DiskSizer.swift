//
//  DiskSizer.swift
//  ReclaimKit
//
//  Measures how much disk space paths actually occupy. Uses *allocated*
//  size (what deletion frees) rather than logical size, which matters
//  for sparse files and APFS clones.
//

import Foundation

/// Thrown when a root path exists but cannot be enumerated at all —
/// most commonly because Reclaim lacks Full Disk Access.
public struct UnreadableRootError: Error, LocalizedError {
    public let path: String

    public var errorDescription: String? {
        localized(
            "sizer.unreadableRoot",
            defaultValue: "“\(path)” exists but could not be read."
        )
    }
}

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
    /// Entries that cannot be read are skipped and counted in
    /// ``DiskMeasurement/inaccessibleItems`` so the caller can flag the
    /// measurement as a lower bound.
    ///
    /// - Parameter failOnUnreadableRoot: When `true` (registry roots), a
    ///   root that exists but cannot be enumerated throws
    ///   ``UnreadableRootError`` — measuring it as zero would be a lie.
    ///   When `false` (a `.removeContents` target's individual children,
    ///   promoted to roots here), an unreadable one is counted in
    ///   ``DiskMeasurement/inaccessibleItems`` instead, so one locked
    ///   child does not make the whole cache look uncleanable.
    /// - Throws: `CancellationError` if the surrounding task is
    ///   cancelled; ``UnreadableRootError`` as described above.
    public func measure(
        _ urls: [URL], failOnUnreadableRoot: Bool = true
    ) throws -> DiskMeasurement {
        var total = DiskMeasurement.zero
        // Spans all roots so a file hard-linked into two of a target's
        // paths is still only counted once. (Deduplication is per-target
        // by design: registry targets never overlap on disk, and scans
        // run concurrently, so a cross-target set would buy nothing.)
        var seenHardLinks = Set<NSObject>()
        for url in urls {
            // A `.removeContents` target passes every top-level child as
            // its own root here, so the between-roots check is what makes
            // Stop responsive on a cache with tens of thousands of them —
            // the per-directory stride below only covers one walk.
            try Task.checkCancellation()
            total.add(try measureOne(
                url, seenHardLinks: &seenHardLinks,
                failOnUnreadableRoot: failOnUnreadableRoot
            ))
        }
        return total
    }

    // MARK: - Implementation

    private static let sizeKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .linkCountKey,
        .fileResourceIdentifierKey,
    ]

    private func measureOne(
        _ url: URL, seenHardLinks: inout Set<NSObject>,
        failOnUnreadableRoot: Bool
    ) throws -> DiskMeasurement {
        let fileManager = FileManager.default

        // A symlink's deletion frees only the link inode, and following
        // it would measure (and later imply deleting) content outside
        // the target. Treat it as a single, size-less entry.
        if let type = (try? fileManager.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType,
           type == .typeSymbolicLink {
            return DiskMeasurement(bytes: 0, fileCount: 1)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .zero
        }

        // Single file (e.g. Docker.raw): read its size directly. A stat
        // failure here is an unreadable item, not a zero-byte one — count
        // it so the measurement is honestly flagged a lower bound rather
        // than silently under-reported.
        guard isDirectory.boolValue else {
            guard let values = try? url.resourceValues(forKeys: Self.sizeKeys) else {
                return DiskMeasurement(bytes: 0, fileCount: 1, inaccessibleItems: 1)
            }
            let bytes = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            return DiskMeasurement(bytes: bytes, fileCount: 1)
        }

        // Directory: deep enumeration, skipping nothing (hidden files
        // count — they occupy space too). Unreadable entries are skipped
        // via the error handler and counted; a failure on the root itself
        // means the whole measurement would be a lie, so that throws.
        let rootPath = url.resolvingSymlinksInPath().path
        var rootUnreadable = false
        var inaccessible = 0

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(Self.sizeKeys),
            options: [],
            errorHandler: { failedURL, _ in
                if failedURL.resolvingSymlinksInPath().path == rootPath {
                    rootUnreadable = true
                } else {
                    inaccessible += 1
                }
                return true
            }
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
            // Distinguish "couldn't read this entry" (a lower-bound
            // inaccessible item) from "read it, and it isn't a regular
            // file" (a directory/symlink we legitimately skip). The old
            // combined guard silently dropped the former.
            guard let values = try? item.resourceValues(forKeys: Self.sizeKeys) else {
                inaccessible += 1
                continue
            }
            guard values.isRegularFile == true else { continue }
            fileCount += 1

            // A hard-linked file occupies its allocation once, however
            // many directory entries point at it. (APFS clones share
            // extents through distinct inodes and cannot be detected
            // this cheaply; sizes remain an upper bound for clones.)
            if let linkCount = values.linkCount, linkCount > 1,
               let identifier = values.fileResourceIdentifier as? NSObject,
               !seenHardLinks.insert(identifier).inserted {
                continue
            }
            bytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        if rootUnreadable {
            // A genuine registry root that can't be read is a failure;
            // a promoted `.removeContents` child is merely one more
            // inaccessible item (a lower-bound flag), not a target-wide
            // failure.
            if failOnUnreadableRoot {
                throw UnreadableRootError(path: url.path)
            }
            return DiskMeasurement(bytes: 0, fileCount: 0, inaccessibleItems: 1)
        }
        return DiskMeasurement(bytes: bytes, fileCount: fileCount, inaccessibleItems: inaccessible)
    }
}
