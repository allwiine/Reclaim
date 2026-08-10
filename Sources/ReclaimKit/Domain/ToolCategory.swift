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
    case gameEngines
    case aiTools
    case packageManagers
    case containers
    case jvm
    case webTools
    case cloudDevOps
    case embedded
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
        case .gameEngines:
            localized("category.gameEngines.title", defaultValue: "Game Engines")
        case .aiTools:
            localized("category.aiTools.title", defaultValue: "AI Tools")
        case .packageManagers:
            localized("category.packageManagers.title", defaultValue: "Package Managers")
        case .containers:
            localized("category.containers.title", defaultValue: "Containers & VMs")
        case .jvm:
            localized("category.jvm.title", defaultValue: "Java & JVM")
        case .webTools:
            localized("category.webTools.title", defaultValue: "Web & JS Tools")
        case .cloudDevOps:
            localized("category.cloudDevOps.title", defaultValue: "Cloud & DevOps")
        case .embedded:
            localized("category.embedded.title", defaultValue: "Embedded & IoT")
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
        case .gameEngines: "gamecontroller"
        case .aiTools: "sparkles"
        case .packageManagers: "shippingbox"
        case .containers: "cube"
        case .jvm: "cup.and.saucer"
        case .webTools: "globe"
        case .cloudDevOps: "cloud"
        case .embedded: "cpu"
        case .otherTools: "wrench.and.screwdriver"
        }
    }
}
