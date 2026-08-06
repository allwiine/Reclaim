//
//  ToolCategory.swift
//  ReclaimKit
//
//  Grouping used by the sidebar and the overview chart. Declaration
//  order defines display order.
//

import Foundation

/// The family of developer tooling a ``CleanupTarget`` belongs to.
public enum ToolCategory: String, CaseIterable, Identifiable, Sendable {
    case xcode
    case android
    case aiTools
    case packageManagers
    case otherTools

    public var id: String { rawValue }

    /// Human-readable name shown in the sidebar.
    public var title: String {
        switch self {
        case .xcode: "Xcode & Simulators"
        case .android: "Android Studio"
        case .aiTools: "Claude & AI Tools"
        case .packageManagers: "Package Managers"
        case .otherTools: "Other Dev Tools"
        }
    }

    /// SF Symbol name shown next to the title.
    public var systemImage: String {
        switch self {
        case .xcode: "hammer"
        case .android: "iphone.gen1"
        case .aiTools: "sparkles"
        case .packageManagers: "shippingbox"
        case .otherTools: "wrench.and.screwdriver"
        }
    }
}
