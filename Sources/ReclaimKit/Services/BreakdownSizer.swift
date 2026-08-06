//
//  BreakdownSizer.swift
//  ReclaimKit
//
//  Sizes the individual items inside a measured target so the UI can
//  show where the space actually is ("largest contents"). Computed on
//  demand — never as part of the scan, which would double every walk.
//

import Foundation

/// One row of a target's "largest contents" breakdown.
public struct BreakdownEntry: Sendable, Equatable, Identifiable {
    /// Stable identity, distinct from `name`: two entries with the same
    /// display name (e.g. same-named roots under different parents) must
    /// not collide in a `ForEach`. Defaults to `name` when no sharper
    /// identity is available.
    public let id: String
    /// Display name — the item's file name, or a "+ N more" aggregate.
    public let name: String
    public let bytes: Int64
    /// How many items this row stands for (1, except the aggregate tail).
    public let itemCount: Int

    public init(id: String? = nil, name: String, bytes: Int64, itemCount: Int = 1) {
        self.id = id ?? name
        self.name = name
        self.bytes = bytes
        self.itemCount = itemCount
    }
}

/// Measures each of a target's scan-time cleanup items individually.
///
/// Blocking and cancellation-aware like ``DiskSizer``; run off the
/// main actor. Unreadable items are skipped — the breakdown is
/// illustrative, the authoritative total remains the scan measurement.
public struct BreakdownSizer: Sendable {
    private let sizer: DiskSizer

    public init(sizer: DiskSizer = DiskSizer()) {
        self.sizer = sizer
    }

    /// The largest items of a measured target, biggest first, with
    /// everything past `limit` collapsed into a single aggregate row.
    ///
    /// - Throws: `CancellationError` when the surrounding task is
    ///   cancelled; a partial breakdown is never returned.
    public func largestContents(of status: TargetStatus, limit: Int = 5) throws -> [BreakdownEntry] {
        // For `.removeContents` the cleanup paths are the directory's
        // children — exactly the granularity worth showing. For
        // `.removePaths` (and single files) fall back to the roots.
        let items = status.cleanupPaths.isEmpty ? status.resolvedPaths : status.cleanupPaths

        var measured: [BreakdownEntry] = []
        for url in items {
            try Task.checkCancellation()
            do {
                let measurement = try sizer.measure([url])
                measured.append(BreakdownEntry(
                    id: url.path, name: url.lastPathComponent, bytes: measurement.bytes
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }

        measured.sort { $0.bytes > $1.bytes }
        guard measured.count > limit, limit >= 1 else { return measured }

        let shown = measured.prefix(limit - 1)
        let tail = measured.dropFirst(limit - 1)
        let aggregate = BreakdownEntry(
            name: localized(
                "breakdown.moreItems",
                defaultValue: "+ \(tail.count) more items"
            ),
            bytes: tail.reduce(0) { $0 + $1.bytes },
            itemCount: tail.count
        )
        return Array(shown) + [aggregate]
    }
}
