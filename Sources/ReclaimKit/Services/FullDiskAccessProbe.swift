//
//  FullDiskAccessProbe.swift
//  ReclaimKit
//
//  Detects whether the process can read TCC-protected locations.
//  Several registry targets live under paths macOS guards with Full
//  Disk Access; without it they would quietly measure as empty, so the
//  app shows a banner when this probe reports denial.
//

import Foundation

/// Checks readability of sentinel files that are TCC-protected on a
/// real system. Injectable `home` and sentinels keep it testable with
/// plain POSIX permissions.
public struct FullDiskAccessProbe: Sendable {
    /// `~`-relative or absolute paths of files that require Full Disk
    /// Access to *open* (metadata access may still succeed without it).
    public let sentinelPaths: [String]
    public let home: URL

    /// The per-user TCC database: present on effectively every modern
    /// macOS account and unreadable without Full Disk Access.
    public static let defaultSentinels = [
        "~/Library/Application Support/com.apple.TCC/TCC.db"
    ]

    public init(
        sentinelPaths: [String] = Self.defaultSentinels,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.sentinelPaths = sentinelPaths
        self.home = home
    }

    /// - Returns: `true` if a sentinel could be opened for reading,
    ///   `false` if opening was denied, `nil` if no sentinel exists
    ///   (indeterminate — do not nag the user).
    public func check() -> Bool? {
        for pattern in sentinelPaths {
            let path =
                pattern.hasPrefix("~") ? home.path + pattern.dropFirst() : pattern
            let url = URL(filePath: path)

            do {
                let handle = try FileHandle(forReadingFrom: url)
                try? handle.close()
                return true
            } catch let error as NSError {
                if Self.isPermissionDenial(error) {
                    return false
                }
                // Missing or otherwise unopenable sentinel: try the next.
            }
        }
        return nil
    }

    /// Walks the error chain: Foundation wraps EPERM/EACCES in varying
    /// Cocoa codes, so the underlying POSIX error is the reliable signal.
    private static func isPermissionDenial(_ error: NSError) -> Bool {
        if error.domain == NSPOSIXErrorDomain,
           error.code == Int(EACCES) || error.code == Int(EPERM) {
            return true
        }
        if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError {
            return true
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isPermissionDenial(underlying)
        }
        return false
    }
}
