//
//  VolumeSpace.swift
//  ReclaimKit
//
//  Capacity of the volume that holds the user's data, for the overview
//  disk card. Read-only and cheap — a single resource-values call.
//

import Foundation

/// Capacity snapshot of one volume.
public struct VolumeSpace: Sendable, Equatable {
    public let totalBytes: Int64
    public let availableBytes: Int64
    /// The user-visible volume name (e.g. "Macintosh HD", localized by
    /// the system), or `nil` when the volume does not report one.
    public let localizedName: String?

    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }

    public init(totalBytes: Int64, availableBytes: Int64, localizedName: String? = nil) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.localizedName = localizedName
    }
}

/// Reads capacity for the volume containing a URL — the home directory
/// by default, since that is where every cleanup target lives.
public struct VolumeSpaceProbe: Sendable {
    public init() {}

    public func measure(
        volumeContaining url: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> VolumeSpace? {
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeLocalizedNameKey,
        ]), let total = values.volumeTotalCapacity else { return nil }

        // "Important usage" matches Finder: it counts purgeable space
        // (APFS snapshots the system frees on demand) as available.
        // Fall back to the plain figure when it is unavailable or zero.
        let important = values.volumeAvailableCapacityForImportantUsage
        let plain = values.volumeAvailableCapacity.map(Int64.init)
        guard let available = important.flatMap({ $0 > 0 ? $0 : nil }) ?? plain else {
            return nil
        }
        return VolumeSpace(
            totalBytes: Int64(total),
            availableBytes: available,
            localizedName: values.volumeLocalizedName
        )
    }
}
