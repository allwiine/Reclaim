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
    case dotNet
    case aiTools
    case packageManagers
    case otherTools

    public var id: String { rawValue }

    /// Human-readable name shown in the sidebar.
    public var title: String {
        switch self {
        case .xcode:
            localized("category.xcode.title", defaultValue: "Xcode & Simulators")
        case .android:
            localized("category.android.title", defaultValue: "Android Studio")
        case .dotNet:
            localized("category.dotNet.title", defaultValue: ".NET & Visual Studio")
        case .aiTools:
            localized("category.aiTools.title", defaultValue: "Claude & AI Tools")
        case .packageManagers:
            localized("category.packageManagers.title", defaultValue: "Package Managers")
        case .otherTools:
            localized("category.otherTools.title", defaultValue: "Other Dev Tools")
        }
    }

    /// SF Symbol name shown next to the title.
    public var systemImage: String {
        switch self {
        case .xcode: "hammer"
        case .android: "iphone.gen1"
        case .dotNet: "curlybraces"
        case .aiTools: "sparkles"
        case .packageManagers: "shippingbox"
        case .otherTools: "wrench.and.screwdriver"
        }
    }
}
