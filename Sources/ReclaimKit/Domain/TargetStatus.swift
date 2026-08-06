//
//  TargetStatus.swift
//  ReclaimKit
//
//  Value types describing scan results. Kept UI-free; formatting
//  belongs to the app layer.
//

import Foundation

/// The on-disk footprint of one or more paths.
public struct DiskMeasurement: Sendable, Equatable {
    /// Allocated bytes (what the disk actually loses), not logical size.
    public var bytes: Int64
    /// Number of regular files counted.
    public var fileCount: Int
    /// Entries the walk could not read (usually missing Full Disk
    /// Access). Non-zero means `bytes` is a lower bound.
    public var inaccessibleItems: Int

    public static let zero = DiskMeasurement(bytes: 0, fileCount: 0)

    public init(bytes: Int64, fileCount: Int, inaccessibleItems: Int = 0) {
        self.bytes = bytes
        self.fileCount = fileCount
        self.inaccessibleItems = inaccessibleItems
    }

    /// Accumulate another measurement into this one.
    public mutating func add(_ other: DiskMeasurement) {
        bytes += other.bytes
        fileCount += other.fileCount
        inaccessibleItems += other.inaccessibleItems
    }
}

/// Lifecycle state of a single ``CleanupTarget`` in the current session.
public enum TargetStatus: Sendable, Equatable {
    /// Not scanned yet.
    case idle
    /// A scan is in flight.
    case scanning
    /// Scanned successfully. `resolvedPaths` are the concrete locations
    /// (globs expanded) that the measurement covers and that cleanup
    /// will operate on.
    case measured(DiskMeasurement, resolvedPaths: [URL])
    /// None of the target's path patterns exist on this machine.
    case notInstalled
    /// The target is command-based; its reclaimable size is unknown
    /// until the command runs.
    case unmeasurable
    /// Scanning failed (most commonly: missing Full Disk Access).
    case failed(message: String)

    /// Measured bytes, or `nil` when no measurement is available.
    public var bytes: Int64? {
        if case .measured(let measurement, _) = self { return measurement.bytes }
        return nil
    }

    /// Concrete paths cleanup should operate on, if known.
    public var resolvedPaths: [URL] {
        if case .measured(_, let paths) = self { return paths }
        return []
    }
}
