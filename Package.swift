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
/// MIRROR: the generated Xcode app target does not inherit these — any
/// change here must be mirrored into project.yml's "Swift settings
/// mirror" block, or the xcodegen build (local .app, release archive)
/// diverges from `swift build`. CI's app-build job catches drift.
let sharedSwiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

/// Settings for the app-facing targets — `ReclaimAppCore`, `Reclaim`, and
/// their test targets: Swift 6.2 "approachable concurrency".
///
/// `.defaultIsolation(MainActor.self)` makes every unannotated declaration
/// main-actor-isolated, which is the truth for observable UI state — most
/// of what these targets contain. The real concurrency boundary is marked
/// explicitly from the other side: each blocking filesystem call sits
/// behind a named `@concurrent` worker, and the value types that cross the
/// boundary are `nonisolated`. `ReclaimKit` stays on `sharedSwiftSettings`
/// (nonisolated by default) deliberately — the Kit *is* the off-main work,
/// so defaulting it to `MainActor` would fight its own purpose.
/// See docs/ARCHITECTURE.md § Concurrency.
let mainActorByDefault: [SwiftSetting] =
    sharedSwiftSettings + [.defaultIsolation(MainActor.self)]

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
            resources: [.process("Resources"), .copy("Catalogue")],
            swiftSettings: sharedSwiftSettings
        ),
        .target(
            name: "ReclaimAppCore",
            dependencies: ["ReclaimKit"],
            resources: [.process("Resources")],
            swiftSettings: mainActorByDefault
        ),
        .executableTarget(
            name: "Reclaim",
            dependencies: ["ReclaimKit", "ReclaimAppCore"],
            resources: [.process("Resources")],
            swiftSettings: mainActorByDefault
        ),
        .testTarget(
            name: "ReclaimKitTests",
            dependencies: ["ReclaimKit"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "ReclaimAppCoreTests",
            dependencies: ["ReclaimAppCore"],
            swiftSettings: mainActorByDefault
        ),
        .testTarget(
            name: "LocalizationLintTests",
            swiftSettings: mainActorByDefault
        ),
    ]
)
