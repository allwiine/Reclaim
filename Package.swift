// swift-tools-version: 6.2
//
//  Package.swift
//  Reclaim — a native macOS utility for finding and cleaning wasted
//  developer storage (Xcode, Android Studio, Claude Code, package
//  managers, and friends).
//
//  Layout
//  ──────
//  • ReclaimKit     – UI-free core: domain model, target registry,
//                     scanning and cleanup services. Fully unit-tested.
//  • ReclaimAppCore – UI-free app state: AppModel + CleanSummary.
//                     Imports ReclaimKit + Observation only, so the
//                     whole orchestration layer is unit-testable.
//  • Reclaim        – The SwiftUI app. Views only.
//  • ReclaimKitTests / ReclaimAppCoreTests – Swift Testing suites.
//
//  The package builds and runs directly ("open Package.swift" in Xcode,
//  or `swift run Reclaim`). An optional XcodeGen spec (project.yml) is
//  provided for producing a distributable .app bundle.

import PackageDescription

/// Shared compiler settings.
///
/// swift-tools-version 6.2 already enables the Swift 6 language mode
/// (strict, compile-time data-race safety). The upcoming features below
/// are safe, forward-looking hygiene flags.
///
/// Deliberate decision: we do NOT enable `.defaultIsolation(MainActor.self)`
/// ("single-threaded by default"). This app has a real concurrency
/// boundary — filesystem scanning must stay off the main actor — so
/// explicit isolation annotations (`@MainActor` on UI/state, `nonisolated`
/// on workers) document that boundary better than a module-wide default.
/// See docs/ARCHITECTURE.md § Concurrency.
let sharedSwiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "Reclaim",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "Reclaim", targets: ["Reclaim"]),
        .library(name: "ReclaimKit", targets: ["ReclaimKit"]),
        .library(name: "ReclaimAppCore", targets: ["ReclaimAppCore"]),
    ],
    targets: [
        .target(
            name: "ReclaimKit",
            resources: [.process("Resources")],
            swiftSettings: sharedSwiftSettings
        ),
        // TEMPORARY — one-shot migration of the Swift registries to the
        // JSON catalogue. Deleted once the migration lands.
        .executableTarget(
            name: "catalogue-migrate",
            dependencies: ["ReclaimKit"],
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "ReclaimAppCore",
            dependencies: ["ReclaimKit"],
            resources: [.process("Resources")],
            swiftSettings: sharedSwiftSettings
        ),
        .executableTarget(
            name: "Reclaim",
            dependencies: ["ReclaimKit", "ReclaimAppCore"],
            resources: [.process("Resources")],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "ReclaimKitTests",
            dependencies: ["ReclaimKit"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "ReclaimAppCoreTests",
            dependencies: ["ReclaimAppCore"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "LocalizationLintTests",
            swiftSettings: sharedSwiftSettings
        ),
    ]
)
