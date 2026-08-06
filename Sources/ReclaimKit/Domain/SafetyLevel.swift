//
//  SafetyLevel.swift
//  ReclaimKit
//
//  How risky it is to clean a given target. The scale is deliberately
//  coarse (three levels) so the UI can communicate it at a glance.
//

import Foundation

/// The consequence class of cleaning a target.
///
/// The rule used consistently across the registry:
/// - ``safe``:        The tool regenerates the data automatically and you
///                    will barely notice (build caches, logs, scratch data).
/// - ``caution``:     The data can be restored, but doing so costs time,
///                    bandwidth, or history (re-downloading models, losing
///                    the ability to resume old sessions).
/// - ``destructive``: Deletes things you configured or created yourself
///                    (e.g. Android emulators). Review before cleaning.
public enum SafetyLevel: Int, CaseIterable, Comparable, Sendable {
    case safe = 0
    case caution = 1
    case destructive = 2

    /// Short label shown in badges.
    public var title: String {
        switch self {
        case .safe: "Safe"
        case .caution: "Caution"
        case .destructive: "Destructive"
        }
    }

    /// One-sentence explanation used in help text and tooltips.
    public var explanation: String {
        switch self {
        case .safe:
            "Regenerated automatically the next time the tool runs."
        case .caution:
            "Restorable, but re-downloading or losing history costs time."
        case .destructive:
            "Removes things you created or configured. Review carefully."
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
