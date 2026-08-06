//
//  Formatters.swift
//  Reclaim
//
//  Shared display formatting. Keeping this in one place guarantees
//  every byte count in the app reads identically. (The compact design
//  formats live with the other tokens in DesignSystem/Theme.swift.)
//

import Foundation
import ReclaimAppCore
import ReclaimKit

extension AppModel {
    /// The user-visible name of the volume the disk cards describe,
    /// falling back to a generic label until the probe reports one.
    var volumeDisplayName: String {
        volumeSpace?.localizedName
            ?? localized("disk.startupDisk", defaultValue: "Startup Disk")
    }
}

extension CleanupTarget {
    /// The terminal command a tool-managed target wants the user to
    /// run, extracted from the backticked part of its instructions
    /// (e.g. "Run `go clean -modcache` in Terminal." → "go clean -modcache").
    var manualCommand: String? {
        guard case .manual(let instructions) = strategy else { return nil }
        guard let match = instructions.firstMatch(of: /`([^`]+)`/) else { return nil }
        return String(match.1)
    }

    /// The instructions of a `.manual` strategy, if any.
    var manualInstructions: String? {
        guard case .manual(let instructions) = strategy else { return nil }
        return instructions
    }
}
