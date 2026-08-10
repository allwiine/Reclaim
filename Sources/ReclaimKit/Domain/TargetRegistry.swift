//
//  TargetRegistry.swift
//  ReclaimKit
//
//  The single source of truth for everything Reclaim knows how to
//  inspect and clean. To support a new tool, add one `CleanupTarget`
//  here — no other code changes required. Invariants (unique ids,
//  sensible patterns) are enforced by ReclaimKitTests/RegistryTests.
//
//  Conventions
//  ───────────
//  • Prefer `.removeContents` for cache roots (tools expect the folder
//    to exist) and `.removePaths` only when removing the item itself
//    is the point.
//  • Never register user data (auth files, settings, source code).
//    For Claude Code specifically: `~/.claude.json`, `~/.claude/settings.json`
//    and `~/.claude/plugins` hold auth/config and are intentionally absent.
//  • Multiple candidate patterns per target are fine — non-existent
//    paths are dropped at scan time.
//  • Display text goes through `localized(_:defaultValue:)` with keys
//    derived from the target id (`target.<id>.name/.summary/.note/
//    .instructions`); both locale catalogues must carry every key
//    (enforced by LocalizationTests).
//

import Foundation

/// Namespace for the built-in target catalogue.
public enum TargetRegistry {
    /// All targets, in display order within their categories.
    public static let all: [CleanupTarget] =
        xcode + android + dotNet + gameEngines + aiTools + packageManagers + containers + jvmTools
            + webTools + cloudDevOps + embedded + otherTools

    /// Convenience: targets grouped by category, preserving order.
    public static func targets(in category: ToolCategory) -> [CleanupTarget] {
        all.filter { $0.category == category }
    }

    // MARK: - Xcode & Apple toolchain

    static let xcode: [CleanupTarget] = [
        CleanupTarget(
            id: "xcode-derived-data",
            name: localized(
                "target.xcode-derived-data.name",
                defaultValue: "Derived data"
            ),
            summary: localized(
                "target.xcode-derived-data.summary",
                defaultValue: "Build products, indexes and module caches for every project you have opened. Rebuilt on the next build."
            ),
            category: .xcode,
            safety: .safe,
            pathPatterns: ["~/Library/Developer/Xcode/DerivedData"],
            strategy: .removeContents,
            note: localized(
                "target.xcode-derived-data.note",
                defaultValue: "The next build of each project will be a clean build."
            ),
            relatedAppBundleIDs: ["com.apple.dt.Xcode"]
        ),
        CleanupTarget(
            id: "xcode-device-support",
            name: localized(
                "target.xcode-device-support.name",
                defaultValue: "Device support files"
            ),
            summary: localized(
                "target.xcode-device-support.summary",
                defaultValue: "Debug symbols copied from every iPhone, iPad, Watch and Apple TV you have ever plugged in. Re-copied automatically when a device reconnects."
            ),
            category: .xcode,
            safety: .safe,
            pathPatterns: [
                "~/Library/Developer/Xcode/iOS DeviceSupport",
                "~/Library/Developer/Xcode/watchOS DeviceSupport",
                "~/Library/Developer/Xcode/tvOS DeviceSupport",
                "~/Library/Developer/Xcode/visionOS DeviceSupport",
            ],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.apple.dt.Xcode"]
        ),
        CleanupTarget(
            id: "xcode-archives",
            name: localized(
                "target.xcode-archives.name",
                defaultValue: "Archives"
            ),
            summary: localized(
                "target.xcode-archives.summary",
                defaultValue: "App archives with dSYMs, used to distribute builds and symbolicate crash reports."
            ),
            category: .xcode,
            safety: .caution,
            pathPatterns: ["~/Library/Developer/Xcode/Archives"],
            strategy: .removeContents,
            note: localized(
                "target.xcode-archives.note",
                defaultValue: "Keep archives for versions that are live on the App Store — you need their dSYMs to read crash reports."
            ),
            relatedAppBundleIDs: ["com.apple.dt.Xcode"]
        ),
        CleanupTarget(
            id: "xcode-simulator-caches",
            name: localized(
                "target.xcode-simulator-caches.name",
                defaultValue: "Simulator caches"
            ),
            summary: localized(
                "target.xcode-simulator-caches.summary",
                defaultValue: "CoreSimulator's cache directory, including dyld caches for simulator runtimes."
            ),
            category: .xcode,
            safety: .safe,
            pathPatterns: ["~/Library/Developer/CoreSimulator/Caches"],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.apple.dt.Xcode", "com.apple.iphonesimulator"]
        ),
        CleanupTarget(
            id: "xcode-previews",
            name: localized(
                "target.xcode-previews.name",
                defaultValue: "SwiftUI Previews data"
            ),
            summary: localized(
                "target.xcode-previews.summary",
                defaultValue: "Simulator devices and build artifacts created by the SwiftUI preview canvas."
            ),
            category: .xcode,
            safety: .safe,
            pathPatterns: ["~/Library/Developer/Xcode/UserData/Previews"],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.apple.dt.Xcode"]
        ),
        CleanupTarget(
            id: "xcode-caches",
            name: localized(
                "target.xcode-caches.name",
                defaultValue: "Xcode caches"
            ),
            summary: localized(
                "target.xcode-caches.summary",
                defaultValue: "Xcode's general cache folder, including the documentation cache."
            ),
            category: .xcode,
            safety: .safe,
            pathPatterns: [
                "~/Library/Caches/com.apple.dt.Xcode",
                "~/Library/Caches/com.apple.dt.Xcode.DocumentationCache",
            ],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.apple.dt.Xcode"]
        ),
        CleanupTarget(
            id: "xcode-unavailable-simulators",
            name: localized(
                "target.xcode-unavailable-simulators.name",
                defaultValue: "Unavailable simulators"
            ),
            summary: localized(
                "target.xcode-unavailable-simulators.summary",
                defaultValue: "Simulator devices left behind by runtimes that are no longer installed."
            ),
            category: .xcode,
            safety: .safe,
            pathPatterns: [],
            strategy: .command(CommandSpec(
                executablePath: "/usr/bin/xcrun",
                arguments: ["simctl", "delete", "unavailable"],
                displayCommand: "xcrun simctl delete unavailable",
                availabilityProbePattern: "~/Library/Developer/CoreSimulator"
            )),
            note: localized(
                "target.xcode-unavailable-simulators.note",
                defaultValue: "Size is only known after cleaning — simctl decides what qualifies."
            )
        ),
        CleanupTarget(
            id: "xcode-device-logs",
            name: localized(
                "target.xcode-device-logs.name",
                defaultValue: "Device logs"
            ),
            summary: localized(
                "target.xcode-device-logs.summary",
                defaultValue: "Console logs collected from physical devices in Xcode's Devices window."
            ),
            category: .xcode,
            safety: .safe,
            pathPatterns: ["~/Library/Developer/Xcode/iOS Device Logs"],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.apple.dt.Xcode"]
        ),
        CleanupTarget(
            id: "xcode-xctest-devices",
            name: localized(
                "target.xcode-xctest-devices.name",
                defaultValue: "Test simulator clones"
            ),
            summary: localized(
                "target.xcode-xctest-devices.summary",
                defaultValue: "Simulator clones created for parallel testing. Recreated on the next test run."
            ),
            category: .xcode,
            safety: .safe,
            pathPatterns: ["~/Library/Developer/XCTestDevices"],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.apple.dt.Xcode"]
        ),
    ]

    // MARK: - Android Studio & Gradle

    static let android: [CleanupTarget] = [
        CleanupTarget(
            id: "gradle-caches",
            name: localized(
                "target.gradle-caches.name",
                defaultValue: "Gradle caches"
            ),
            summary: localized(
                "target.gradle-caches.summary",
                defaultValue: "Downloaded dependencies and transformed artifacts shared by all Gradle builds. Re-downloaded on demand."
            ),
            category: .android,
            safety: .safe,
            pathPatterns: ["~/.gradle/caches"],
            strategy: .removeContents,
            note: localized(
                "target.gradle-caches.note",
                defaultValue: "The next build re-downloads what it needs — expect it to be slower once."
            ),
            relatedAppBundleIDs: ["com.google.android.studio"]
        ),
        CleanupTarget(
            id: "gradle-daemon",
            name: localized(
                "target.gradle-daemon.name",
                defaultValue: "Gradle daemon logs"
            ),
            summary: localized(
                "target.gradle-daemon.summary",
                defaultValue: "Logs and registry files written by every Gradle daemon that ever ran."
            ),
            category: .android,
            safety: .safe,
            pathPatterns: ["~/.gradle/daemon"],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.google.android.studio"]
        ),
        CleanupTarget(
            id: "gradle-wrapper-dists",
            name: localized(
                "target.gradle-wrapper-dists.name",
                defaultValue: "Gradle wrapper distributions"
            ),
            summary: localized(
                "target.gradle-wrapper-dists.summary",
                defaultValue: "Every Gradle version any wrapper script has ever downloaded. Projects re-download their pinned version when needed."
            ),
            category: .android,
            safety: .safe,
            pathPatterns: ["~/.gradle/wrapper/dists"],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.google.android.studio"]
        ),
        CleanupTarget(
            id: "android-studio-caches",
            name: localized(
                "target.android-studio-caches.name",
                defaultValue: "Android Studio caches"
            ),
            summary: localized(
                "target.android-studio-caches.summary",
                defaultValue: "IDE caches and indexes, kept per Android Studio version — old versions linger forever."
            ),
            category: .android,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/Google/AndroidStudio*"],
            strategy: .removePaths,
            note: localized(
                "target.android-studio-caches.note",
                defaultValue: "Android Studio rebuilds its index on next launch."
            ),
            relatedAppBundleIDs: ["com.google.android.studio"]
        ),
        CleanupTarget(
            id: "android-build-cache",
            name: localized(
                "target.android-build-cache.name",
                defaultValue: "Android build cache"
            ),
            summary: localized(
                "target.android-build-cache.summary",
                defaultValue: "The legacy Android build cache and temporary SDK files."
            ),
            category: .android,
            safety: .safe,
            pathPatterns: ["~/.android/build-cache", "~/.android/cache"],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.google.android.studio"]
        ),
        CleanupTarget(
            id: "android-system-images",
            name: localized(
                "target.android-system-images.name",
                defaultValue: "SDK system images"
            ),
            summary: localized(
                "target.android-system-images.summary",
                defaultValue: "Emulator system images downloaded via the SDK Manager. Each API level is multiple gigabytes."
            ),
            category: .android,
            safety: .caution,
            pathPatterns: ["~/Library/Android/sdk/system-images"],
            strategy: .removeContents,
            note: localized(
                "target.android-system-images.note",
                defaultValue: "Existing emulators using a deleted image stop booting until it is re-downloaded from the SDK Manager."
            ),
            relatedAppBundleIDs: ["com.google.android.studio"]
        ),
        CleanupTarget(
            id: "android-avds",
            name: localized(
                "target.android-avds.name",
                defaultValue: "Emulator devices (AVDs)"
            ),
            summary: localized(
                "target.android-avds.summary",
                defaultValue: "Your Android Virtual Devices, including their user data and snapshots."
            ),
            category: .android,
            safety: .destructive,
            pathPatterns: ["~/.android/avd"],
            strategy: .removeContents,
            note: localized(
                "target.android-avds.note",
                defaultValue: "Deletes the emulators themselves, not just caches. Recreate them from Device Manager afterwards."
            ),
            relatedAppBundleIDs: ["com.google.android.studio"]
        ),
        CleanupTarget(
            id: "gradle-build-scan",
            name: localized(
                "target.gradle-build-scan.name",
                defaultValue: "Gradle build-scan data"
            ),
            summary: localized(
                "target.gradle-build-scan.summary",
                defaultValue: "Build-scan payloads staged locally by the Gradle build scan plugin."
            ),
            category: .android,
            safety: .safe,
            pathPatterns: ["~/.gradle/build-scan-data"],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.google.android.studio"]
        ),
        CleanupTarget(
            id: "kotlin-native-cache",
            name: localized(
                "target.kotlin-native-cache.name",
                defaultValue: "Kotlin/Native toolchains"
            ),
            summary: localized(
                "target.kotlin-native-cache.summary",
                defaultValue: "Toolchains and dependency caches for Kotlin/Native builds. Each version is hundreds of megabytes."
            ),
            category: .android,
            safety: .safe,
            pathPatterns: ["~/.konan"],
            strategy: .removeContents,
            note: localized(
                "target.kotlin-native-cache.note",
                defaultValue: "Gradle re-downloads what it needs on the next Kotlin/Native build."
            )
        ),
    ]

    // MARK: - .NET & Visual Studio

    static let dotNet: [CleanupTarget] = [
        CleanupTarget(
            id: "nuget-packages",
            name: localized(
                "target.nuget-packages.name",
                defaultValue: "NuGet global packages"
            ),
            summary: localized(
                "target.nuget-packages.summary",
                defaultValue: "Every package version any .NET project has ever restored, kept forever. Projects re-restore what they still use on the next build."
            ),
            category: .dotNet,
            safety: .safe,
            pathPatterns: ["~/.nuget/packages"],
            strategy: .removeContents,
            note: localized(
                "target.nuget-packages.note",
                defaultValue: "Equivalent to `dotnet nuget locals global-packages --clear` — the next restore re-downloads what is needed."
            ),
            relatedAppBundleIDs: ["com.jetbrains.rider", "com.microsoft.VSCode"]
        ),
        CleanupTarget(
            id: "nuget-http-cache",
            name: localized(
                "target.nuget-http-cache.name",
                defaultValue: "NuGet download caches"
            ),
            summary: localized(
                "target.nuget-http-cache.summary",
                defaultValue: "HTTP responses and plugin output NuGet caches while restoring. Rebuilt on demand."
            ),
            category: .dotNet,
            safety: .safe,
            pathPatterns: ["~/.local/share/NuGet"],
            strategy: .removeContents,
            note: localized(
                "target.nuget-http-cache.note",
                defaultValue: "Equivalent to `dotnet nuget locals http-cache --clear`."
            )
        ),
        CleanupTarget(
            id: "dotnet-workload-packs",
            name: localized(
                "target.dotnet-workload-packs.name",
                defaultValue: "Orphaned workload packs"
            ),
            summary: localized(
                "target.dotnet-workload-packs.summary",
                defaultValue: "SDK workload packs (MAUI, wasm-tools and friends) left behind by updated or uninstalled SDKs. The .NET CLI removes them itself."
            ),
            category: .dotNet,
            safety: .safe,
            pathPatterns: [],
            strategy: .command(CommandSpec(
                executablePath: "/usr/local/share/dotnet/dotnet",
                arguments: ["workload", "clean"],
                displayCommand: "dotnet workload clean",
                availabilityProbePattern: "/usr/local/share/dotnet/sdk"
            )),
            note: localized(
                "target.dotnet-workload-packs.note",
                defaultValue: "Size is only known after cleaning — the .NET CLI decides what is orphaned. SDKs installed via Homebrew are not detected."
            )
        ),
        CleanupTarget(
            id: "azure-functions-bundles",
            name: localized(
                "target.azure-functions-bundles.name",
                defaultValue: "Azure Functions extension bundles"
            ),
            summary: localized(
                "target.azure-functions-bundles.summary",
                defaultValue: "Extension bundles and templates downloaded by Azure Functions Core Tools. Re-downloaded the next time `func` runs."
            ),
            category: .dotNet,
            safety: .safe,
            pathPatterns: ["~/.azure-functions-core-tools"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "vsmac-leftovers",
            name: localized(
                "target.vsmac-leftovers.name",
                defaultValue: "Visual Studio for Mac leftovers"
            ),
            summary: localized(
                "target.vsmac-leftovers.summary",
                defaultValue: "Caches and logs from Visual Studio for Mac, retired in 2024. Nothing reads them anymore."
            ),
            category: .dotNet,
            safety: .safe,
            pathPatterns: [
                "~/Library/Caches/VisualStudio",
                "~/Library/Logs/VisualStudio",
            ],
            strategy: .removePaths
        ),
        CleanupTarget(
            id: "xamarin-caches",
            name: localized(
                "target.xamarin-caches.name",
                defaultValue: "Xamarin caches"
            ),
            summary: localized(
                "target.xamarin-caches.summary",
                defaultValue: "Build-agent and archive caches from the retired Xamarin toolchain."
            ),
            category: .dotNet,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/Xamarin"],
            strategy: .removePaths
        ),
    ]

    // MARK: - Game engines

    static let gameEngines: [CleanupTarget] = [
        CleanupTarget(
            id: "unity-caches",
            name: localized(
                "target.unity-caches.name",
                defaultValue: "Unity caches"
            ),
            summary: localized(
                "target.unity-caches.summary",
                defaultValue: "Unity's global package cache and editor caches, shared by all projects. Rebuilt and re-downloaded as projects open."
            ),
            category: .gameEngines,
            safety: .safe,
            pathPatterns: [
                "~/Library/Unity/cache",
                "~/Library/Caches/Unity",
            ],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.unity3d.UnityEditor5.x"]
        ),
        CleanupTarget(
            id: "unity-asset-store-cache",
            name: localized(
                "target.unity-asset-store-cache.name",
                defaultValue: "Unity Asset Store downloads"
            ),
            summary: localized(
                "target.unity-asset-store-cache.summary",
                defaultValue: "Asset Store packages downloaded through the Unity editor. Kept forever, even for assets you no longer import."
            ),
            category: .gameEngines,
            safety: .caution,
            pathPatterns: ["~/Library/Unity/Asset Store-5.x"],
            strategy: .removeContents,
            note: localized(
                "target.unity-asset-store-cache.note",
                defaultValue: "Assets re-download from My Assets in the Package Manager when needed."
            ),
            relatedAppBundleIDs: ["com.unity3d.UnityEditor5.x"]
        ),
        CleanupTarget(
            id: "unreal-derived-data",
            name: localized(
                "target.unreal-derived-data.name",
                defaultValue: "Unreal derived data"
            ),
            summary: localized(
                "target.unreal-derived-data.summary",
                defaultValue: "Unreal Engine's shared derived-data cache, including the Zen storage used by UE 5.4 and newer. Shaders and textures rebuild on demand."
            ),
            category: .gameEngines,
            safety: .caution,
            pathPatterns: [
                "~/Library/Application Support/Epic/UnrealEngine/Common/DerivedDataCache",
                "~/Library/Application Support/Epic/UnrealEngine/Common/Zen/Data",
            ],
            strategy: .removeContents,
            note: localized(
                "target.unreal-derived-data.note",
                defaultValue: "Quit Unreal Editor before cleaning. The next open of each project recompiles shaders, which takes a while."
            )
        ),
        CleanupTarget(
            id: "godot-caches",
            name: localized(
                "target.godot-caches.name",
                defaultValue: "Godot caches"
            ),
            summary: localized(
                "target.godot-caches.summary",
                defaultValue: "Editor and shader caches kept by Godot. Rebuilt on demand."
            ),
            category: .gameEngines,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/Godot"],
            strategy: .removeContents,
            relatedAppBundleIDs: ["org.godotengine.godot"]
        ),
        CleanupTarget(
            id: "godot-export-templates",
            name: localized(
                "target.godot-export-templates.name",
                defaultValue: "Godot export templates"
            ),
            summary: localized(
                "target.godot-export-templates.summary",
                defaultValue: "Export templates for every Godot version ever installed. Old versions linger after upgrades."
            ),
            category: .gameEngines,
            safety: .caution,
            pathPatterns: ["~/Library/Application Support/Godot/export_templates"],
            strategy: .removeContents,
            note: localized(
                "target.godot-export-templates.note",
                defaultValue: "Download the matching templates from the editor before exporting a project again."
            ),
            relatedAppBundleIDs: ["org.godotengine.godot"]
        ),
    ]

    // MARK: - AI tooling

    static let aiTools: [CleanupTarget] = [
        CleanupTarget(
            id: "claude-code-cli-caches",
            name: localized(
                "target.claude-code-cli-caches.name",
                defaultValue: "Claude Code CLI caches"
            ),
            summary: localized(
                "target.claude-code-cli-caches.summary",
                defaultValue: "Per-project diagnostic output and MCP logs written by Claude Code's Node harness. This folder grows without bound under heavy use."
            ),
            category: .aiTools,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/claude-cli-nodejs"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "claude-code-scratch",
            name: localized(
                "target.claude-code-scratch.name",
                defaultValue: "Claude Code logs & scratch data"
            ),
            summary: localized(
                "target.claude-code-scratch.summary",
                defaultValue: "Debug logs, shell snapshots and telemetry scratch data. Recreated on the next run."
            ),
            category: .aiTools,
            safety: .safe,
            pathPatterns: [
                "~/.claude/debug",
                "~/.claude/shell-snapshots",
                "~/.claude/statsig",
            ],
            strategy: .removeContents,
            note: localized(
                "target.claude-code-scratch.note",
                defaultValue: "Auth (~/.claude.json), settings and plugins are never touched by Reclaim."
            )
        ),
        CleanupTarget(
            id: "claude-code-transcripts",
            name: localized(
                "target.claude-code-transcripts.name",
                defaultValue: "Claude Code session history"
            ),
            summary: localized(
                "target.claude-code-transcripts.summary",
                defaultValue: "Conversation transcripts for every project (~/.claude/projects). Cleaning removes the ability to resume or rewind past sessions."
            ),
            category: .aiTools,
            safety: .caution,
            pathPatterns: ["~/.claude/projects", "~/.claude/file-history"],
            strategy: .removeContents,
            note: localized(
                "target.claude-code-transcripts.note",
                defaultValue: "Prefer setting \"cleanupPeriodDays\" in ~/.claude/settings.json so Claude Code prunes old transcripts automatically."
            )
        ),
        CleanupTarget(
            id: "claude-desktop-caches",
            name: localized(
                "target.claude-desktop-caches.name",
                defaultValue: "Claude Desktop caches"
            ),
            summary: localized(
                "target.claude-desktop-caches.summary",
                defaultValue: "Rendering and code caches for the Claude desktop app. Rebuilt on next launch."
            ),
            category: .aiTools,
            safety: .safe,
            pathPatterns: [
                "~/Library/Caches/com.anthropic.claudefordesktop",
                "~/Library/Application Support/Claude/Cache",
                "~/Library/Application Support/Claude/Code Cache",
                "~/Library/Application Support/Claude/GPUCache",
            ],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.anthropic.claudefordesktop"]
        ),
        CleanupTarget(
            id: "chatgpt-desktop-caches",
            name: localized(
                "target.chatgpt-desktop-caches.name",
                defaultValue: "ChatGPT Desktop caches"
            ),
            summary: localized(
                "target.chatgpt-desktop-caches.summary",
                defaultValue: "Rendering and update caches for OpenAI's ChatGPT desktop app. Rebuilt on next launch."
            ),
            category: .aiTools,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/com.openai.chat"],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.openai.chat"]
        ),
        CleanupTarget(
            id: "codex-cli-sessions",
            name: localized(
                "target.codex-cli-sessions.name",
                defaultValue: "Codex CLI session history"
            ),
            summary: localized(
                "target.codex-cli-sessions.summary",
                defaultValue: "Session transcripts and logs written by OpenAI's Codex CLI. Cleaning removes the ability to resume past sessions."
            ),
            category: .aiTools,
            safety: .caution,
            pathPatterns: [
                "~/.codex/sessions",
                "~/.codex/archived_sessions",
                "~/.codex/log",
            ],
            strategy: .removeContents,
            note: localized(
                "target.codex-cli-sessions.note",
                defaultValue: "Auth and config in ~/.codex (auth.json, config.toml) are never touched by Reclaim."
            )
        ),
        CleanupTarget(
            id: "copilot-cli-data",
            name: localized(
                "target.copilot-cli-data.name",
                defaultValue: "GitHub Copilot CLI logs & sessions"
            ),
            summary: localized(
                "target.copilot-cli-data.summary",
                defaultValue: "Logs and resumable session state kept by the GitHub Copilot CLI. Cleaning removes the ability to resume past sessions."
            ),
            category: .aiTools,
            safety: .caution,
            pathPatterns: [
                "~/.copilot/logs",
                "~/.copilot/history-session-state",
            ],
            strategy: .removeContents,
            note: localized(
                "target.copilot-cli-data.note",
                defaultValue: "Copilot's config in ~/.copilot is never touched by Reclaim."
            )
        ),
        CleanupTarget(
            id: "gemini-cli-scratch",
            name: localized(
                "target.gemini-cli-scratch.name",
                defaultValue: "Gemini CLI scratch data"
            ),
            summary: localized(
                "target.gemini-cli-scratch.summary",
                defaultValue: "Per-project temp files, logs and checkpoints written by Google's Gemini CLI."
            ),
            category: .aiTools,
            safety: .safe,
            pathPatterns: ["~/.gemini/tmp"],
            strategy: .removeContents,
            note: localized(
                "target.gemini-cli-scratch.note",
                defaultValue: "Settings and auth in ~/.gemini are never touched by Reclaim."
            )
        ),
        CleanupTarget(
            id: "cursor-caches",
            name: localized(
                "target.cursor-caches.name",
                defaultValue: "Cursor caches"
            ),
            summary: localized(
                "target.cursor-caches.summary",
                defaultValue: "Extension host, rendering and code caches for the Cursor editor."
            ),
            category: .aiTools,
            safety: .safe,
            pathPatterns: [
                "~/Library/Application Support/Cursor/Cache",
                "~/Library/Application Support/Cursor/CachedData",
                "~/Library/Application Support/Cursor/Code Cache",
                "~/Library/Application Support/Cursor/GPUCache",
            ],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.todesktop.230313mzl4w4u92"]
        ),
        CleanupTarget(
            id: "windsurf-caches",
            name: localized(
                "target.windsurf-caches.name",
                defaultValue: "Windsurf caches"
            ),
            summary: localized(
                "target.windsurf-caches.summary",
                defaultValue: "Extension host, rendering and code caches for the Windsurf editor."
            ),
            category: .aiTools,
            safety: .safe,
            pathPatterns: [
                "~/Library/Application Support/Windsurf/Cache",
                "~/Library/Application Support/Windsurf/CachedData",
                "~/Library/Application Support/Windsurf/Code Cache",
                "~/Library/Application Support/Windsurf/GPUCache",
            ],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.exafunction.windsurf"]
        ),
        CleanupTarget(
            id: "antigravity-caches",
            name: localized(
                "target.antigravity-caches.name",
                defaultValue: "Antigravity caches"
            ),
            summary: localized(
                "target.antigravity-caches.summary",
                defaultValue: "Extension host, rendering and code caches for Google's Antigravity IDE."
            ),
            category: .aiTools,
            safety: .safe,
            pathPatterns: [
                "~/Library/Application Support/Antigravity/Cache",
                "~/Library/Application Support/Antigravity/CachedData",
                "~/Library/Application Support/Antigravity/Code Cache",
                "~/Library/Application Support/Antigravity/GPUCache",
            ],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "cline-tasks",
            name: localized(
                "target.cline-tasks.name",
                defaultValue: "Cline task history"
            ),
            summary: localized(
                "target.cline-tasks.summary",
                defaultValue: "Conversation history and file checkpoints for every Cline task, stored inside VS Code, Cursor and Windsurf. Grows by gigabytes under heavy use."
            ),
            category: .aiTools,
            safety: .caution,
            pathPatterns: [
                "~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/tasks",
                "~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/checkpoints",
                "~/Library/Application Support/Cursor/User/globalStorage/saoudrizwan.claude-dev/tasks",
                "~/Library/Application Support/Cursor/User/globalStorage/saoudrizwan.claude-dev/checkpoints",
                "~/Library/Application Support/Windsurf/User/globalStorage/saoudrizwan.claude-dev/tasks",
                "~/Library/Application Support/Windsurf/User/globalStorage/saoudrizwan.claude-dev/checkpoints",
            ],
            strategy: .removeContents,
            note: localized(
                "target.cline-tasks.note",
                defaultValue: "Cline's settings and MCP configuration are never touched by Reclaim."
            ),
            relatedAppBundleIDs: [
                "com.microsoft.VSCode",
                "com.todesktop.230313mzl4w4u92",
                "com.exafunction.windsurf",
            ]
        ),
        CleanupTarget(
            id: "roo-code-tasks",
            name: localized(
                "target.roo-code-tasks.name",
                defaultValue: "Roo Code task history"
            ),
            summary: localized(
                "target.roo-code-tasks.summary",
                defaultValue: "Conversation history and file checkpoints for every Roo Code task, stored inside VS Code, Cursor and Windsurf."
            ),
            category: .aiTools,
            safety: .caution,
            pathPatterns: [
                "~/Library/Application Support/Code/User/globalStorage/rooveterinaryinc.roo-cline/tasks",
                "~/Library/Application Support/Code/User/globalStorage/rooveterinaryinc.roo-cline/checkpoints",
                "~/Library/Application Support/Cursor/User/globalStorage/rooveterinaryinc.roo-cline/tasks",
                "~/Library/Application Support/Cursor/User/globalStorage/rooveterinaryinc.roo-cline/checkpoints",
                "~/Library/Application Support/Windsurf/User/globalStorage/rooveterinaryinc.roo-cline/tasks",
                "~/Library/Application Support/Windsurf/User/globalStorage/rooveterinaryinc.roo-cline/checkpoints",
            ],
            strategy: .removeContents,
            note: localized(
                "target.roo-code-tasks.note",
                defaultValue: "Roo Code's settings and MCP configuration are never touched by Reclaim."
            ),
            relatedAppBundleIDs: [
                "com.microsoft.VSCode",
                "com.todesktop.230313mzl4w4u92",
                "com.exafunction.windsurf",
            ]
        ),
        CleanupTarget(
            id: "continue-index",
            name: localized(
                "target.continue-index.name",
                defaultValue: "Continue codebase index"
            ),
            summary: localized(
                "target.continue-index.summary",
                defaultValue: "Codebase index built by the Continue extension for @codebase context. Rebuilt on next indexing."
            ),
            category: .aiTools,
            safety: .safe,
            pathPatterns: ["~/.continue/index"],
            strategy: .removeContents,
            note: localized(
                "target.continue-index.note",
                defaultValue: "Config and session history in ~/.continue are never touched by Reclaim."
            )
        ),
        CleanupTarget(
            id: "aider-caches",
            name: localized(
                "target.aider-caches.name",
                defaultValue: "Aider caches"
            ),
            summary: localized(
                "target.aider-caches.summary",
                defaultValue: "Model metadata and version-check caches kept by aider."
            ),
            category: .aiTools,
            safety: .safe,
            pathPatterns: ["~/.aider/caches"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "goose-data",
            name: localized(
                "target.goose-data.name",
                defaultValue: "Goose sessions & logs"
            ),
            summary: localized(
                "target.goose-data.summary",
                defaultValue: "Session transcripts and logs from Block's Goose agent. Cleaning removes the ability to resume past sessions."
            ),
            category: .aiTools,
            safety: .caution,
            pathPatterns: [
                "~/.local/share/goose/sessions",
                "~/.local/state/goose/logs",
            ],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "opencode-data",
            name: localized(
                "target.opencode-data.name",
                defaultValue: "OpenCode caches & logs"
            ),
            summary: localized(
                "target.opencode-data.summary",
                defaultValue: "Downloaded provider bundles and logs kept by the OpenCode agent."
            ),
            category: .aiTools,
            safety: .safe,
            pathPatterns: [
                "~/.cache/opencode",
                "~/.local/share/opencode/log",
            ],
            strategy: .removeContents,
            note: localized(
                "target.opencode-data.note",
                defaultValue: "Auth and session storage in ~/.local/share/opencode are never touched by Reclaim."
            )
        ),
        CleanupTarget(
            id: "ollama-models",
            name: localized(
                "target.ollama-models.name",
                defaultValue: "Ollama models"
            ),
            summary: localized(
                "target.ollama-models.summary",
                defaultValue: "Local LLM weights pulled with `ollama pull`. Often tens of gigabytes."
            ),
            category: .aiTools,
            safety: .caution,
            pathPatterns: ["~/.ollama/models"],
            strategy: .removeContents,
            note: localized(
                "target.ollama-models.note",
                defaultValue: "Models must be re-downloaded to use them again. To remove selectively, use `ollama rm <model>`."
            )
        ),
        CleanupTarget(
            id: "huggingface-cache",
            name: localized(
                "target.huggingface-cache.name",
                defaultValue: "Hugging Face cache"
            ),
            summary: localized(
                "target.huggingface-cache.summary",
                defaultValue: "Models and datasets cached by transformers, diffusers and the huggingface_hub."
            ),
            category: .aiTools,
            safety: .caution,
            pathPatterns: ["~/.cache/huggingface"],
            strategy: .removeContents,
            note: localized(
                "target.huggingface-cache.note",
                defaultValue: "Anything still needed is re-downloaded on next use."
            )
        ),
        CleanupTarget(
            id: "lmstudio-models",
            name: localized(
                "target.lmstudio-models.name",
                defaultValue: "LM Studio models"
            ),
            summary: localized(
                "target.lmstudio-models.summary",
                defaultValue: "Model files downloaded through LM Studio."
            ),
            category: .aiTools,
            safety: .caution,
            pathPatterns: [
                "~/.lmstudio/models",
                "~/.cache/lm-studio/models",
            ],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "llamacpp-cache",
            name: localized(
                "target.llamacpp-cache.name",
                defaultValue: "llama.cpp model cache"
            ),
            summary: localized(
                "target.llamacpp-cache.summary",
                defaultValue: "Models downloaded by llama.cpp tools with the -hf flag. Often several gigabytes."
            ),
            category: .aiTools,
            safety: .caution,
            pathPatterns: ["~/Library/Caches/llama.cpp"],
            strategy: .removeContents,
            note: localized(
                "target.llamacpp-cache.note",
                defaultValue: "Models are re-downloaded on next use."
            )
        ),
        CleanupTarget(
            id: "pytorch-hub-cache",
            name: localized(
                "target.pytorch-hub-cache.name",
                defaultValue: "PyTorch caches"
            ),
            summary: localized(
                "target.pytorch-hub-cache.summary",
                defaultValue: "Model weights and datasets downloaded by PyTorch Hub and torchvision."
            ),
            category: .aiTools,
            safety: .caution,
            pathPatterns: ["~/.cache/torch"],
            strategy: .removeContents,
            note: localized(
                "target.pytorch-hub-cache.note",
                defaultValue: "Weights are re-downloaded on next use."
            )
        ),
    ]

    // MARK: - Package managers & toolchains

    static let packageManagers: [CleanupTarget] = [
        CleanupTarget(
            id: "homebrew-cache",
            name: localized(
                "target.homebrew-cache.name",
                defaultValue: "Homebrew downloads"
            ),
            summary: localized(
                "target.homebrew-cache.summary",
                defaultValue: "Downloaded bottles and old formula versions kept by Homebrew."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/Homebrew"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "npm-cache",
            name: localized(
                "target.npm-cache.name",
                defaultValue: "npm cache"
            ),
            summary: localized(
                "target.npm-cache.summary",
                defaultValue: "npm's content-addressable package cache."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/.npm/_cacache"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "pnpm-store",
            name: localized(
                "target.pnpm-store.name",
                defaultValue: "pnpm store"
            ),
            summary: localized(
                "target.pnpm-store.summary",
                defaultValue: "pnpm's global content-addressable store. Packages are re-fetched per project as needed."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/pnpm/store", "~/.pnpm-store"],
            strategy: .removeContents,
            note: localized(
                "target.pnpm-store.note",
                defaultValue: "Prefer `pnpm store prune` to drop only unreferenced packages."
            )
        ),
        CleanupTarget(
            id: "yarn-cache",
            name: localized(
                "target.yarn-cache.name",
                defaultValue: "Yarn cache"
            ),
            summary: localized(
                "target.yarn-cache.summary",
                defaultValue: "Yarn's global package cache."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/Yarn"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "pip-cache",
            name: localized(
                "target.pip-cache.name",
                defaultValue: "pip cache"
            ),
            summary: localized(
                "target.pip-cache.summary",
                defaultValue: "Wheels and HTTP responses cached by pip."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/pip"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "uv-cache",
            name: localized(
                "target.uv-cache.name",
                defaultValue: "uv cache"
            ),
            summary: localized(
                "target.uv-cache.summary",
                defaultValue: "The uv package manager's wheel and source cache."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/uv", "~/.cache/uv"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "cocoapods-cache",
            name: localized(
                "target.cocoapods-cache.name",
                defaultValue: "CocoaPods cache"
            ),
            summary: localized(
                "target.cocoapods-cache.summary",
                defaultValue: "Downloaded pod releases and spec data."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/CocoaPods"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "spm-cache",
            name: localized(
                "target.spm-cache.name",
                defaultValue: "Swift Package Manager cache"
            ),
            summary: localized(
                "target.spm-cache.summary",
                defaultValue: "Checked-out repositories and manifests cached by SwiftPM (shared by Xcode and the CLI)."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/org.swift.swiftpm"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "cargo-registry",
            name: localized(
                "target.cargo-registry.name",
                defaultValue: "Cargo registry"
            ),
            summary: localized(
                "target.cargo-registry.summary",
                defaultValue: "Downloaded Rust crates and registry indexes."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/.cargo/registry"],
            strategy: .removeContents,
            note: localized(
                "target.cargo-registry.note",
                defaultValue: "Crates are re-downloaded on the next `cargo build`."
            )
        ),
        CleanupTarget(
            id: "go-build-cache",
            name: localized(
                "target.go-build-cache.name",
                defaultValue: "Go build cache"
            ),
            summary: localized(
                "target.go-build-cache.summary",
                defaultValue: "Compiled Go build artifacts."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/go-build"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "go-module-cache",
            name: localized(
                "target.go-module-cache.name",
                defaultValue: "Go module cache"
            ),
            summary: localized(
                "target.go-module-cache.summary",
                defaultValue: "Downloaded Go modules. Go marks these files read-only, so deletion must go through the Go toolchain."
            ),
            category: .packageManagers,
            safety: .caution,
            pathPatterns: ["~/go/pkg/mod"],
            strategy: .manual(instructions: localized(
                "target.go-module-cache.instructions",
                defaultValue: "Run `go clean -modcache` in Terminal."
            ))
        ),
        CleanupTarget(
            id: "deno-cache",
            name: localized(
                "target.deno-cache.name",
                defaultValue: "Deno cache"
            ),
            summary: localized(
                "target.deno-cache.summary",
                defaultValue: "Remote modules and generated code cached by Deno. Re-downloaded on demand."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/deno"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "npm-logs",
            name: localized(
                "target.npm-logs.name",
                defaultValue: "npm logs"
            ),
            summary: localized(
                "target.npm-logs.summary",
                defaultValue: "Debug logs npm writes for every invocation. They are never pruned."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/.npm/_logs"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "yarn-berry-cache",
            name: localized(
                "target.yarn-berry-cache.name",
                defaultValue: "Yarn Berry cache"
            ),
            summary: localized(
                "target.yarn-berry-cache.summary",
                defaultValue: "Yarn Berry's global compressed package cache."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/.yarn/berry/cache"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "node-gyp-cache",
            name: localized(
                "target.node-gyp-cache.name",
                defaultValue: "node-gyp headers"
            ),
            summary: localized(
                "target.node-gyp-cache.summary",
                defaultValue: "Node.js headers and libraries downloaded for building native addons."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/node-gyp", "~/.node-gyp"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "poetry-cache",
            name: localized(
                "target.poetry-cache.name",
                defaultValue: "Poetry cache"
            ),
            summary: localized(
                "target.poetry-cache.summary",
                defaultValue: "Package artifacts and metadata cached by the Poetry package manager."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/pypoetry"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "conda-pkgs",
            name: localized("target.conda-pkgs.name", defaultValue: "conda package cache"),
            summary: localized(
                "target.conda-pkgs.summary",
                defaultValue: "Downloaded and extracted packages shared by all conda environments."
            ),
            category: .packageManagers,
            safety: .caution,
            pathPatterns: [
                "~/miniconda3/pkgs",
                "~/anaconda3/pkgs",
                "~/miniforge3/pkgs",
                "~/mambaforge/pkgs",
                "~/.conda/pkgs",
            ],
            strategy: .removeContents,
            note: localized(
                "target.conda-pkgs.note",
                defaultValue: "Prefer `conda clean --all` to remove only unused packages. Environments hard-link into this cache."
            )
        ),
        CleanupTarget(
            id: "pyenv-versions",
            name: localized("target.pyenv-versions.name", defaultValue: "pyenv Python versions"),
            summary: localized(
                "target.pyenv-versions.summary",
                defaultValue: "Every Python version installed through pyenv, including virtualenvs created by pyenv-virtualenv."
            ),
            category: .packageManagers,
            safety: .destructive,
            pathPatterns: ["~/.pyenv/versions"],
            strategy: .removeContents,
            note: localized(
                "target.pyenv-versions.note",
                defaultValue: "Reinstall with `pyenv install <version>`."
            )
        ),
        CleanupTarget(
            id: "uv-python-toolchains",
            name: localized("target.uv-python-toolchains.name", defaultValue: "uv Python toolchains"),
            summary: localized(
                "target.uv-python-toolchains.summary",
                defaultValue: "Python versions installed and managed by uv. Re-downloaded on demand."
            ),
            category: .packageManagers,
            safety: .caution,
            pathPatterns: ["~/.local/share/uv/python"],
            strategy: .removeContents,
            note: localized(
                "target.uv-python-toolchains.note",
                defaultValue: "Existing virtual environments link into these toolchains and break until the version is reinstalled."
            )
        ),
        CleanupTarget(
            id: "pipx-cache",
            name: localized("target.pipx-cache.name", defaultValue: "pipx cache & logs"),
            summary: localized(
                "target.pipx-cache.summary",
                defaultValue: "Temporary environments and logs kept by pipx. Installed tools are not touched."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: [
                "~/.cache/pipx",
                "~/.local/pipx/logs",
                "~/.local/share/pipx/logs",
            ],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "pub-cache",
            name: localized("target.pub-cache.name", defaultValue: "pub cache"),
            summary: localized(
                "target.pub-cache.summary",
                defaultValue: "Dart and Flutter packages downloaded by pub. Restored by `flutter pub get` per project."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/.pub-cache"],
            strategy: .removeContents,
            note: localized(
                "target.pub-cache.note",
                defaultValue: "Very old Dart SDKs (before 2.15) stored pub.dev publishing credentials in this folder."
            )
        ),
        CleanupTarget(
            id: "dart-analysis-cache",
            name: localized("target.dart-analysis-cache.name", defaultValue: "Dart analysis cache"),
            summary: localized(
                "target.dart-analysis-cache.summary",
                defaultValue: "Code indexes built by the Dart analysis server. Rebuilt on next analysis."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/.dartServer"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "rustup-toolchains",
            name: localized("target.rustup-toolchains.name", defaultValue: "rustup toolchains"),
            summary: localized(
                "target.rustup-toolchains.summary",
                defaultValue: "Every Rust toolchain installed through rustup. Old nightlies especially pile up, each taking a gigabyte or more."
            ),
            category: .packageManagers,
            safety: .destructive,
            pathPatterns: ["~/.rustup/toolchains"],
            strategy: .removeContents,
            note: localized(
                "target.rustup-toolchains.note",
                defaultValue: "Reinstall with `rustup toolchain install <version>`; builds stop working until then."
            )
        ),
        CleanupTarget(
            id: "rbenv-versions",
            name: localized("target.rbenv-versions.name", defaultValue: "rbenv Ruby versions"),
            summary: localized(
                "target.rbenv-versions.summary",
                defaultValue: "Every Ruby version installed through rbenv, including their installed gems."
            ),
            category: .packageManagers,
            safety: .destructive,
            pathPatterns: ["~/.rbenv/versions"],
            strategy: .removeContents,
            note: localized(
                "target.rbenv-versions.note",
                defaultValue: "Reinstall with `rbenv install <version>`."
            )
        ),
        CleanupTarget(
            id: "mise-cache",
            name: localized("target.mise-cache.name", defaultValue: "mise cache"),
            summary: localized(
                "target.mise-cache.summary",
                defaultValue: "Version lists and downloads cached by the mise version manager. Installed runtimes are not touched."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/mise", "~/.cache/mise"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "composer-cache",
            name: localized("target.composer-cache.name", defaultValue: "Composer cache"),
            summary: localized(
                "target.composer-cache.summary",
                defaultValue: "Package archives cached by PHP's Composer."
            ),
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/.composer/cache", "~/Library/Caches/composer"],
            strategy: .removeContents
        ),
    ]

    // MARK: - Containers & VMs

    static let containers: [CleanupTarget] = [
        CleanupTarget(
            id: "docker-vm-disk",
            name: localized(
                "target.docker-vm-disk.name",
                defaultValue: "Docker VM disk"
            ),
            summary: localized(
                "target.docker-vm-disk.summary",
                defaultValue: "The virtual disk holding all Docker images, containers and volumes. It only shrinks when Docker itself prunes."
            ),
            category: .containers,
            safety: .caution,
            pathPatterns: [
                "~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
                "~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.qcow2",
            ],
            strategy: .manual(instructions: localized(
                "target.docker-vm-disk.instructions",
                defaultValue: "Run `docker system prune -a` (and optionally `--volumes`) in Terminal, then let Docker Desktop compact the disk."
            ))
        ),
        CleanupTarget(
            id: "orbstack-data",
            name: localized("target.orbstack-data.name", defaultValue: "OrbStack data"),
            summary: localized(
                "target.orbstack-data.summary",
                defaultValue: "The disk holding all OrbStack containers, images, volumes and Linux machines."
            ),
            category: .containers,
            safety: .caution,
            pathPatterns: [
                "~/.orbstack",
                "~/Library/Group Containers/HUAQ24HBR6.dev.orbstack/data",
            ],
            strategy: .manual(instructions: localized(
                "target.orbstack-data.instructions",
                defaultValue: "Run `docker system prune -a` in Terminal, or delete machines and volumes in the OrbStack app."
            ))
        ),
        CleanupTarget(
            id: "colima-vm",
            name: localized("target.colima-vm.name", defaultValue: "Colima VMs"),
            summary: localized(
                "target.colima-vm.summary",
                defaultValue: "Virtual machine disks holding all containers and images for Colima instances."
            ),
            category: .containers,
            safety: .caution,
            pathPatterns: ["~/.colima"],
            strategy: .manual(instructions: localized(
                "target.colima-vm.instructions",
                defaultValue: "Run `docker system prune -a` while Colima is running, or `colima delete` to remove an instance entirely."
            ))
        ),
        CleanupTarget(
            id: "lima-vms",
            name: localized("target.lima-vms.name", defaultValue: "Lima VMs"),
            summary: localized(
                "target.lima-vms.summary",
                defaultValue: "Virtual machines created by Lima, including their disks."
            ),
            category: .containers,
            safety: .caution,
            pathPatterns: ["~/.lima"],
            strategy: .manual(instructions: localized(
                "target.lima-vms.instructions",
                defaultValue: "Run `limactl delete <name>` in Terminal to remove a VM you no longer use."
            ))
        ),
        CleanupTarget(
            id: "lima-cache",
            name: localized("target.lima-cache.name", defaultValue: "Lima image cache"),
            summary: localized(
                "target.lima-cache.summary",
                defaultValue: "Base images downloaded for Lima virtual machines. Re-downloaded when a VM is recreated."
            ),
            category: .containers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/lima"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "podman-machines",
            name: localized("target.podman-machines.name", defaultValue: "Podman machines"),
            summary: localized(
                "target.podman-machines.summary",
                defaultValue: "Machines, containers and images managed by Podman."
            ),
            category: .containers,
            safety: .caution,
            pathPatterns: ["~/.local/share/containers"],
            strategy: .manual(instructions: localized(
                "target.podman-machines.instructions",
                defaultValue: "Run `podman system prune -a` in Terminal, or `podman machine rm <name>` to remove a machine."
            ))
        ),
        CleanupTarget(
            id: "vagrant-boxes",
            name: localized("target.vagrant-boxes.name", defaultValue: "Vagrant boxes"),
            summary: localized(
                "target.vagrant-boxes.summary",
                defaultValue: "Base box images downloaded by Vagrant. Each box re-downloads on the next `vagrant up` that needs it."
            ),
            category: .containers,
            safety: .caution,
            pathPatterns: ["~/.vagrant.d/boxes"],
            strategy: .removeContents,
            note: localized(
                "target.vagrant-boxes.note",
                defaultValue: "Running VMs live in your provider (VirtualBox, VMware) and are not touched."
            )
        ),
        CleanupTarget(
            id: "minikube-cache",
            name: localized("target.minikube-cache.name", defaultValue: "minikube cache"),
            summary: localized(
                "target.minikube-cache.summary",
                defaultValue: "Kubernetes images and ISOs cached by minikube. Re-downloaded on the next `minikube start`."
            ),
            category: .containers,
            safety: .safe,
            pathPatterns: ["~/.minikube/cache"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "rancher-desktop-caches",
            name: localized("target.rancher-desktop-caches.name", defaultValue: "Rancher Desktop caches"),
            summary: localized(
                "target.rancher-desktop-caches.summary",
                defaultValue: "Downloaded Kubernetes images and update caches for Rancher Desktop."
            ),
            category: .containers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/rancher-desktop"],
            strategy: .removeContents,
            relatedAppBundleIDs: ["io.rancherdesktop.app"]
        ),
    ]

    // MARK: - Java & JVM

    static let jvmTools: [CleanupTarget] = [
        CleanupTarget(
            id: "maven-repository",
            name: localized("target.maven-repository.name", defaultValue: "Maven local repository"),
            summary: localized(
                "target.maven-repository.summary",
                defaultValue: "Every artifact any Maven or JVM build has ever downloaded, kept forever. The next build re-downloads what it still uses."
            ),
            category: .jvm,
            safety: .safe,
            pathPatterns: ["~/.m2/repository"],
            strategy: .removeContents,
            note: localized(
                "target.maven-repository.note",
                defaultValue: "The next build of each project is slower once."
            )
        ),
        CleanupTarget(
            id: "sdkman-archives",
            name: localized("target.sdkman-archives.name", defaultValue: "SDKMAN archives"),
            summary: localized(
                "target.sdkman-archives.summary",
                defaultValue: "Downloaded SDK archives and temp files kept by SDKMAN. Installed SDKs are not touched."
            ),
            category: .jvm,
            safety: .safe,
            pathPatterns: ["~/.sdkman/archives", "~/.sdkman/tmp"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "coursier-cache",
            name: localized("target.coursier-cache.name", defaultValue: "Coursier cache"),
            summary: localized(
                "target.coursier-cache.summary",
                defaultValue: "Artifacts cached by Coursier for Scala and JVM builds."
            ),
            category: .jvm,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/Coursier", "~/.cache/coursier"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "ivy-cache",
            name: localized("target.ivy-cache.name", defaultValue: "Ivy cache"),
            summary: localized(
                "target.ivy-cache.summary",
                defaultValue: "Artifacts cached by sbt and Apache Ivy builds."
            ),
            category: .jvm,
            safety: .safe,
            pathPatterns: ["~/.ivy2/cache"],
            strategy: .removeContents
        ),
    ]

    // MARK: - Web & JavaScript tools

    static let webTools: [CleanupTarget] = [
        CleanupTarget(
            id: "playwright-browsers",
            name: localized(
                "target.playwright-browsers.name",
                defaultValue: "Playwright browsers"
            ),
            summary: localized(
                "target.playwright-browsers.summary",
                defaultValue: "Browser builds downloaded by Playwright for testing. Each version set is over a gigabyte."
            ),
            category: .webTools,
            safety: .caution,
            pathPatterns: ["~/Library/Caches/ms-playwright"],
            strategy: .removeContents,
            note: localized(
                "target.playwright-browsers.note",
                defaultValue: "Run `npx playwright install` to restore browsers before the next test run."
            )
        ),
        CleanupTarget(
            id: "puppeteer-cache",
            name: localized(
                "target.puppeteer-cache.name",
                defaultValue: "Puppeteer browsers"
            ),
            summary: localized(
                "target.puppeteer-cache.summary",
                defaultValue: "Chrome builds downloaded by Puppeteer."
            ),
            category: .webTools,
            safety: .caution,
            pathPatterns: ["~/.cache/puppeteer"],
            strategy: .removeContents,
            note: localized(
                "target.puppeteer-cache.note",
                defaultValue: "Re-downloaded the next time Puppeteer installs its browser."
            )
        ),
        CleanupTarget(
            id: "bun-install-cache",
            name: localized("target.bun-install-cache.name", defaultValue: "Bun install cache"),
            summary: localized(
                "target.bun-install-cache.summary",
                defaultValue: "Packages cached by Bun's installer. Re-downloaded on demand."
            ),
            category: .webTools,
            safety: .safe,
            pathPatterns: ["~/.bun/install/cache"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "cypress-binaries",
            name: localized("target.cypress-binaries.name", defaultValue: "Cypress binaries"),
            summary: localized(
                "target.cypress-binaries.summary",
                defaultValue: "Every Cypress version ever installed, each around half a gigabyte. Old versions are never pruned."
            ),
            category: .webTools,
            safety: .caution,
            pathPatterns: ["~/Library/Caches/Cypress"],
            strategy: .removeContents,
            note: localized(
                "target.cypress-binaries.note",
                defaultValue: "Run `npx cypress install` to restore the binary before the next test run."
            )
        ),
        CleanupTarget(
            id: "electron-caches",
            name: localized("target.electron-caches.name", defaultValue: "Electron caches"),
            summary: localized(
                "target.electron-caches.summary",
                defaultValue: "Electron builds and build tooling downloaded by electron and electron-builder."
            ),
            category: .webTools,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/electron", "~/Library/Caches/electron-builder"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "corepack-cache",
            name: localized("target.corepack-cache.name", defaultValue: "Corepack cache"),
            summary: localized(
                "target.corepack-cache.summary",
                defaultValue: "Package manager versions (pnpm, Yarn) downloaded by Corepack."
            ),
            category: .webTools,
            safety: .safe,
            pathPatterns: ["~/.cache/node/corepack"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "nvm-node-versions",
            name: localized("target.nvm-node-versions.name", defaultValue: "nvm Node versions"),
            summary: localized(
                "target.nvm-node-versions.summary",
                defaultValue: "Every Node.js version installed through nvm, including their global packages."
            ),
            category: .webTools,
            safety: .destructive,
            pathPatterns: ["~/.nvm/versions/node"],
            strategy: .removeContents,
            note: localized(
                "target.nvm-node-versions.note",
                defaultValue: "Reinstall with `nvm install <version>`; your default version stops working until reinstalled."
            )
        ),
        CleanupTarget(
            id: "prisma-engines-cache",
            name: localized("target.prisma-engines-cache.name", defaultValue: "Prisma engine binaries"),
            summary: localized(
                "target.prisma-engines-cache.summary",
                defaultValue: "Query and schema engine binaries downloaded for every Prisma version a project has ever used."
            ),
            category: .webTools,
            safety: .safe,
            pathPatterns: ["~/.cache/prisma"],
            strategy: .removeContents
        ),
    ]

    // MARK: - Cloud & DevOps

    static let cloudDevOps: [CleanupTarget] = [
        CleanupTarget(
            id: "kubectl-cache",
            name: localized("target.kubectl-cache.name", defaultValue: "kubectl cache"),
            summary: localized(
                "target.kubectl-cache.summary",
                defaultValue: "API discovery and HTTP caches written by kubectl."
            ),
            category: .cloudDevOps,
            safety: .safe,
            pathPatterns: ["~/.kube/cache", "~/.kube/http-cache"],
            strategy: .removeContents,
            note: localized(
                "target.kubectl-cache.note",
                defaultValue: "Your cluster config in ~/.kube/config is never touched."
            )
        ),
        CleanupTarget(
            id: "helm-caches",
            name: localized("target.helm-caches.name", defaultValue: "Helm caches"),
            summary: localized(
                "target.helm-caches.summary",
                defaultValue: "Chart repository indexes and downloaded charts cached by Helm."
            ),
            category: .cloudDevOps,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/helm"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "pulumi-plugins",
            name: localized("target.pulumi-plugins.name", defaultValue: "Pulumi plugins"),
            summary: localized(
                "target.pulumi-plugins.summary",
                defaultValue: "Provider plugins downloaded by Pulumi. Re-downloaded on the next `pulumi up`."
            ),
            category: .cloudDevOps,
            safety: .safe,
            pathPatterns: ["~/.pulumi/plugins"],
            strategy: .removeContents,
            note: localized(
                "target.pulumi-plugins.note",
                defaultValue: "Credentials and workspaces in ~/.pulumi are never touched."
            )
        ),
        CleanupTarget(
            id: "gcloud-logs",
            name: localized("target.gcloud-logs.name", defaultValue: "Google Cloud CLI logs"),
            summary: localized(
                "target.gcloud-logs.summary",
                defaultValue: "Logs written by every gcloud invocation. They are never pruned."
            ),
            category: .cloudDevOps,
            safety: .safe,
            pathPatterns: ["~/.config/gcloud/logs"],
            strategy: .removeContents,
            note: localized(
                "target.gcloud-logs.note",
                defaultValue: "Auth and config in ~/.config/gcloud are never touched."
            )
        ),
        CleanupTarget(
            id: "azure-cli-logs",
            name: localized("target.azure-cli-logs.name", defaultValue: "Azure CLI logs"),
            summary: localized(
                "target.azure-cli-logs.summary",
                defaultValue: "Logs written by the Azure CLI."
            ),
            category: .cloudDevOps,
            safety: .safe,
            pathPatterns: ["~/.azure/logs"],
            strategy: .removeContents,
            note: localized(
                "target.azure-cli-logs.note",
                defaultValue: "Auth in ~/.azure is never touched."
            )
        ),
        CleanupTarget(
            id: "terraform-plugin-cache",
            name: localized("target.terraform-plugin-cache.name", defaultValue: "Terraform plugin cache"),
            summary: localized(
                "target.terraform-plugin-cache.summary",
                defaultValue: "Provider plugins cached when the plugin cache is enabled in .terraformrc. Re-downloaded on the next `terraform init`."
            ),
            category: .cloudDevOps,
            safety: .safe,
            pathPatterns: ["~/.terraform.d/plugin-cache"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "firebase-emulators",
            name: localized("target.firebase-emulators.name", defaultValue: "Firebase emulators"),
            summary: localized(
                "target.firebase-emulators.summary",
                defaultValue: "Emulator binaries (Firestore, Auth, Pub/Sub and friends) downloaded by the Firebase CLI."
            ),
            category: .cloudDevOps,
            safety: .safe,
            pathPatterns: ["~/.cache/firebase/emulators"],
            strategy: .removeContents,
            note: localized(
                "target.firebase-emulators.note",
                defaultValue: "Re-downloaded on the next `firebase emulators:start`."
            )
        ),
    ]

    // MARK: - Embedded & IoT

    static let embedded: [CleanupTarget] = [
        CleanupTarget(
            id: "platformio-cache",
            name: localized(
                "target.platformio-cache.name",
                defaultValue: "PlatformIO cache"
            ),
            summary: localized(
                "target.platformio-cache.summary",
                defaultValue: "Download and HTTP caches kept by PlatformIO Core. Installed platforms, toolchains and libraries are not touched."
            ),
            category: .embedded,
            safety: .safe,
            pathPatterns: ["~/.platformio/.cache"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "arduino-staging",
            name: localized(
                "target.arduino-staging.name",
                defaultValue: "Arduino downloads"
            ),
            summary: localized(
                "target.arduino-staging.summary",
                defaultValue: "Board core and library archives downloaded by the Arduino IDE and CLI. Kept after installation and re-downloaded on demand."
            ),
            category: .embedded,
            safety: .safe,
            pathPatterns: ["~/Library/Arduino15/staging"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "esp-idf-dist",
            name: localized(
                "target.esp-idf-dist.name",
                defaultValue: "ESP-IDF download archives"
            ),
            summary: localized(
                "target.esp-idf-dist.summary",
                defaultValue: "Toolchain and tool archives downloaded by the ESP-IDF installer. The extracted tools stay installed."
            ),
            category: .embedded,
            safety: .safe,
            pathPatterns: ["~/.espressif/dist"],
            strategy: .removeContents
        ),
    ]

    // MARK: - Other developer tools

    static let otherTools: [CleanupTarget] = [
        CleanupTarget(
            id: "vscode-caches",
            name: localized(
                "target.vscode-caches.name",
                defaultValue: "VS Code caches"
            ),
            summary: localized(
                "target.vscode-caches.summary",
                defaultValue: "Extension host, rendering and code caches for Visual Studio Code."
            ),
            category: .otherTools,
            safety: .safe,
            pathPatterns: [
                "~/Library/Application Support/Code/Cache",
                "~/Library/Application Support/Code/CachedData",
                "~/Library/Application Support/Code/Code Cache",
                "~/Library/Application Support/Code/CachedExtensionVSIXs",
            ],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.microsoft.VSCode"]
        ),
        CleanupTarget(
            id: "jetbrains-caches",
            name: localized(
                "target.jetbrains-caches.name",
                defaultValue: "JetBrains IDE caches"
            ),
            summary: localized(
                "target.jetbrains-caches.summary",
                defaultValue: "Caches and indexes for IntelliJ, PyCharm, WebStorm and friends, kept per IDE version."
            ),
            category: .otherTools,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/JetBrains"],
            strategy: .removeContents,
            note: localized(
                "target.jetbrains-caches.note",
                defaultValue: "Each IDE rebuilds its index on next launch."
            )
        ),
        CleanupTarget(
            id: "vscode-workspace-storage",
            name: localized(
                "target.vscode-workspace-storage.name",
                defaultValue: "VS Code workspace storage"
            ),
            summary: localized(
                "target.vscode-workspace-storage.summary",
                defaultValue: "Per-workspace UI state, history and extension data for every folder you have ever opened — entries for deleted projects linger forever."
            ),
            category: .otherTools,
            safety: .caution,
            pathPatterns: ["~/Library/Application Support/Code/User/workspaceStorage"],
            strategy: .removeContents,
            note: localized(
                "target.vscode-workspace-storage.note",
                defaultValue: "Open workspaces recreate their entry, but per-workspace history and unsaved editor state are lost."
            ),
            relatedAppBundleIDs: ["com.microsoft.VSCode"]
        ),
        CleanupTarget(
            id: "pre-commit-cache",
            name: localized(
                "target.pre-commit-cache.name",
                defaultValue: "pre-commit environments"
            ),
            summary: localized(
                "target.pre-commit-cache.summary",
                defaultValue: "Hook environments built by pre-commit. Recreated on the next run in each repository."
            ),
            category: .otherTools,
            safety: .safe,
            pathPatterns: ["~/.cache/pre-commit"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "jetbrains-logs",
            name: localized(
                "target.jetbrains-logs.name",
                defaultValue: "JetBrains IDE logs"
            ),
            summary: localized(
                "target.jetbrains-logs.summary",
                defaultValue: "Log files for IntelliJ, PyCharm, WebStorm and friends, kept per IDE version."
            ),
            category: .otherTools,
            safety: .safe,
            pathPatterns: ["~/Library/Logs/JetBrains"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "zed-caches",
            name: localized(
                "target.zed-caches.name",
                defaultValue: "Zed caches & language servers"
            ),
            summary: localized(
                "target.zed-caches.summary",
                defaultValue: "Caches and auto-downloaded language servers kept by the Zed editor. Re-downloaded on demand."
            ),
            category: .otherTools,
            safety: .safe,
            pathPatterns: [
                "~/Library/Caches/Zed",
                "~/Library/Application Support/Zed/languages",
            ],
            strategy: .removeContents,
            relatedAppBundleIDs: ["dev.zed.Zed"]
        ),
        CleanupTarget(
            id: "ccache-cache",
            name: localized(
                "target.ccache-cache.name",
                defaultValue: "ccache compiler cache"
            ),
            summary: localized(
                "target.ccache-cache.summary",
                defaultValue: "Compiled objects cached by ccache to speed up C and C++ rebuilds. Rebuilt as you compile."
            ),
            category: .otherTools,
            safety: .safe,
            pathPatterns: ["~/.ccache", "~/Library/Caches/ccache"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "sccache-cache",
            name: localized(
                "target.sccache-cache.name",
                defaultValue: "sccache compiler cache"
            ),
            summary: localized(
                "target.sccache-cache.summary",
                defaultValue: "Compilation results cached by sccache for Rust, C and CUDA builds."
            ),
            category: .otherTools,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/Mozilla.sccache"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "bazel-output",
            name: localized(
                "target.bazel-output.name",
                defaultValue: "Bazel output trees"
            ),
            summary: localized(
                "target.bazel-output.summary",
                defaultValue: "Build outputs and repository caches for every Bazel workspace, kept in /private/var/tmp. A running Bazel server holds locks here."
            ),
            category: .otherTools,
            safety: .caution,
            pathPatterns: ["/private/var/tmp/_bazel_*"],
            strategy: .manual(instructions: localized(
                "target.bazel-output.instructions",
                defaultValue: "Run `bazel clean --expunge` in each workspace, or `bazel shutdown` followed by deleting its output tree."
            ))
        ),
    ]
}
