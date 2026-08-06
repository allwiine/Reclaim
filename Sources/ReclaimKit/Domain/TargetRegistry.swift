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
//

import Foundation

/// Namespace for the built-in target catalogue.
public enum TargetRegistry {
    /// All targets, in display order within their categories.
    public static let all: [CleanupTarget] =
        xcode + android + aiTools + packageManagers + otherTools

    /// Convenience: targets grouped by category, preserving order.
    public static func targets(in category: ToolCategory) -> [CleanupTarget] {
        all.filter { $0.category == category }
    }

    // MARK: - Xcode & Apple toolchain

    static let xcode: [CleanupTarget] = [
        CleanupTarget(
            id: "xcode-derived-data",
            name: "Derived data",
            summary: "Build products, indexes and module caches for every project you have opened. Rebuilt on the next build.",
            category: .xcode,
            safety: .safe,
            pathPatterns: ["~/Library/Developer/Xcode/DerivedData"],
            strategy: .removeContents,
            note: "The next build of each project will be a clean build.",
            relatedAppBundleIDs: ["com.apple.dt.Xcode"]
        ),
        CleanupTarget(
            id: "xcode-device-support",
            name: "Device support files",
            summary: "Debug symbols copied from every iPhone, iPad, Watch and Apple TV you have ever plugged in. Re-copied automatically when a device reconnects.",
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
            name: "Archives",
            summary: "App archives with dSYMs, used to distribute builds and symbolicate crash reports.",
            category: .xcode,
            safety: .caution,
            pathPatterns: ["~/Library/Developer/Xcode/Archives"],
            strategy: .removeContents,
            note: "Keep archives for versions that are live on the App Store — you need their dSYMs to read crash reports.",
            relatedAppBundleIDs: ["com.apple.dt.Xcode"]
        ),
        CleanupTarget(
            id: "xcode-simulator-caches",
            name: "Simulator caches",
            summary: "CoreSimulator's cache directory, including dyld caches for simulator runtimes.",
            category: .xcode,
            safety: .safe,
            pathPatterns: ["~/Library/Developer/CoreSimulator/Caches"],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.apple.dt.Xcode", "com.apple.iphonesimulator"]
        ),
        CleanupTarget(
            id: "xcode-previews",
            name: "SwiftUI Previews data",
            summary: "Simulator devices and build artifacts created by the SwiftUI preview canvas.",
            category: .xcode,
            safety: .safe,
            pathPatterns: ["~/Library/Developer/Xcode/UserData/Previews"],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.apple.dt.Xcode"]
        ),
        CleanupTarget(
            id: "xcode-caches",
            name: "Xcode caches",
            summary: "Xcode's general cache folder, including the documentation cache.",
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
            name: "Unavailable simulators",
            summary: "Simulator devices left behind by runtimes that are no longer installed.",
            category: .xcode,
            safety: .safe,
            pathPatterns: [],
            strategy: .command(CommandSpec(
                executablePath: "/usr/bin/xcrun",
                arguments: ["simctl", "delete", "unavailable"],
                displayCommand: "xcrun simctl delete unavailable",
                availabilityProbePattern: "~/Library/Developer/CoreSimulator"
            )),
            note: "Size is only known after cleaning — simctl decides what qualifies."
        ),
    ]

    // MARK: - Android Studio & Gradle

    static let android: [CleanupTarget] = [
        CleanupTarget(
            id: "gradle-caches",
            name: "Gradle caches",
            summary: "Downloaded dependencies and transformed artifacts shared by all Gradle builds. Re-downloaded on demand.",
            category: .android,
            safety: .safe,
            pathPatterns: ["~/.gradle/caches"],
            strategy: .removeContents,
            note: "The next build re-downloads what it needs — expect it to be slower once.",
            relatedAppBundleIDs: ["com.google.android.studio"]
        ),
        CleanupTarget(
            id: "gradle-daemon",
            name: "Gradle daemon logs",
            summary: "Logs and registry files written by every Gradle daemon that ever ran.",
            category: .android,
            safety: .safe,
            pathPatterns: ["~/.gradle/daemon"],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.google.android.studio"]
        ),
        CleanupTarget(
            id: "gradle-wrapper-dists",
            name: "Gradle wrapper distributions",
            summary: "Every Gradle version any wrapper script has ever downloaded. Projects re-download their pinned version when needed.",
            category: .android,
            safety: .safe,
            pathPatterns: ["~/.gradle/wrapper/dists"],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.google.android.studio"]
        ),
        CleanupTarget(
            id: "android-studio-caches",
            name: "Android Studio caches",
            summary: "IDE caches and indexes, kept per Android Studio version — old versions linger forever.",
            category: .android,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/Google/AndroidStudio*"],
            strategy: .removePaths,
            note: "Android Studio rebuilds its index on next launch.",
            relatedAppBundleIDs: ["com.google.android.studio"]
        ),
        CleanupTarget(
            id: "android-build-cache",
            name: "Android build cache",
            summary: "The legacy Android build cache and temporary SDK files.",
            category: .android,
            safety: .safe,
            pathPatterns: ["~/.android/build-cache", "~/.android/cache"],
            strategy: .removeContents,
            relatedAppBundleIDs: ["com.google.android.studio"]
        ),
        CleanupTarget(
            id: "android-system-images",
            name: "SDK system images",
            summary: "Emulator system images downloaded via the SDK Manager. Each API level is multiple gigabytes.",
            category: .android,
            safety: .caution,
            pathPatterns: ["~/Library/Android/sdk/system-images"],
            strategy: .removeContents,
            note: "Existing emulators using a deleted image stop booting until it is re-downloaded from the SDK Manager.",
            relatedAppBundleIDs: ["com.google.android.studio"]
        ),
        CleanupTarget(
            id: "android-avds",
            name: "Emulator devices (AVDs)",
            summary: "Your Android Virtual Devices, including their user data and snapshots.",
            category: .android,
            safety: .destructive,
            pathPatterns: ["~/.android/avd"],
            strategy: .removeContents,
            note: "Deletes the emulators themselves, not just caches. Recreate them from Device Manager afterwards.",
            relatedAppBundleIDs: ["com.google.android.studio"]
        ),
    ]

    // MARK: - Claude & AI tooling

    static let aiTools: [CleanupTarget] = [
        CleanupTarget(
            id: "claude-code-cli-caches",
            name: "Claude Code CLI caches",
            summary: "Per-project diagnostic output and MCP logs written by Claude Code's Node harness. This folder grows without bound under heavy use.",
            category: .aiTools,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/claude-cli-nodejs"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "claude-code-scratch",
            name: "Claude Code logs & scratch data",
            summary: "Debug logs, shell snapshots and telemetry scratch data. Recreated on the next run.",
            category: .aiTools,
            safety: .safe,
            pathPatterns: [
                "~/.claude/debug",
                "~/.claude/shell-snapshots",
                "~/.claude/statsig",
            ],
            strategy: .removeContents,
            note: "Auth (~/.claude.json), settings and plugins are never touched by Reclaim."
        ),
        CleanupTarget(
            id: "claude-code-transcripts",
            name: "Claude Code session history",
            summary: "Conversation transcripts for every project (~/.claude/projects). Cleaning removes the ability to resume or rewind past sessions.",
            category: .aiTools,
            safety: .caution,
            pathPatterns: ["~/.claude/projects", "~/.claude/file-history"],
            strategy: .removeContents,
            note: "Prefer setting \"cleanupPeriodDays\" in ~/.claude/settings.json so Claude Code prunes old transcripts automatically."
        ),
        CleanupTarget(
            id: "claude-desktop-caches",
            name: "Claude Desktop caches",
            summary: "Rendering and code caches for the Claude desktop app. Rebuilt on next launch.",
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
            id: "ollama-models",
            name: "Ollama models",
            summary: "Local LLM weights pulled with `ollama pull`. Often tens of gigabytes.",
            category: .aiTools,
            safety: .caution,
            pathPatterns: ["~/.ollama/models"],
            strategy: .removeContents,
            note: "Models must be re-downloaded to use them again. To remove selectively, use `ollama rm <model>`."
        ),
        CleanupTarget(
            id: "huggingface-cache",
            name: "Hugging Face cache",
            summary: "Models and datasets cached by transformers, diffusers and the huggingface_hub.",
            category: .aiTools,
            safety: .caution,
            pathPatterns: ["~/.cache/huggingface"],
            strategy: .removeContents,
            note: "Anything still needed is re-downloaded on next use."
        ),
        CleanupTarget(
            id: "lmstudio-models",
            name: "LM Studio models",
            summary: "Model files downloaded through LM Studio.",
            category: .aiTools,
            safety: .caution,
            pathPatterns: [
                "~/.lmstudio/models",
                "~/.cache/lm-studio/models",
            ],
            strategy: .removeContents
        ),
    ]

    // MARK: - Package managers & toolchains

    static let packageManagers: [CleanupTarget] = [
        CleanupTarget(
            id: "homebrew-cache",
            name: "Homebrew downloads",
            summary: "Downloaded bottles and old formula versions kept by Homebrew.",
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/Homebrew"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "npm-cache",
            name: "npm cache",
            summary: "npm's content-addressable package cache.",
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/.npm/_cacache"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "pnpm-store",
            name: "pnpm store",
            summary: "pnpm's global content-addressable store. Packages are re-fetched per project as needed.",
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/pnpm/store", "~/.pnpm-store"],
            strategy: .removeContents,
            note: "Prefer `pnpm store prune` to drop only unreferenced packages."
        ),
        CleanupTarget(
            id: "yarn-cache",
            name: "Yarn cache",
            summary: "Yarn's global package cache.",
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/Yarn"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "pip-cache",
            name: "pip cache",
            summary: "Wheels and HTTP responses cached by pip.",
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/pip"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "uv-cache",
            name: "uv cache",
            summary: "The uv package manager's wheel and source cache.",
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/uv", "~/.cache/uv"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "cocoapods-cache",
            name: "CocoaPods cache",
            summary: "Downloaded pod releases and spec data.",
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/CocoaPods"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "spm-cache",
            name: "Swift Package Manager cache",
            summary: "Checked-out repositories and manifests cached by SwiftPM (shared by Xcode and the CLI).",
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/org.swift.swiftpm"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "cargo-registry",
            name: "Cargo registry",
            summary: "Downloaded Rust crates and registry indexes.",
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/.cargo/registry"],
            strategy: .removeContents,
            note: "Crates are re-downloaded on the next `cargo build`."
        ),
        CleanupTarget(
            id: "go-build-cache",
            name: "Go build cache",
            summary: "Compiled Go build artifacts.",
            category: .packageManagers,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/go-build"],
            strategy: .removeContents
        ),
        CleanupTarget(
            id: "go-module-cache",
            name: "Go module cache",
            summary: "Downloaded Go modules. Go marks these files read-only, so deletion must go through the Go toolchain.",
            category: .packageManagers,
            safety: .caution,
            pathPatterns: ["~/go/pkg/mod"],
            strategy: .manual(instructions: "Run `go clean -modcache` in Terminal.")
        ),
    ]

    // MARK: - Other developer tools

    static let otherTools: [CleanupTarget] = [
        CleanupTarget(
            id: "vscode-caches",
            name: "VS Code caches",
            summary: "Extension host, rendering and code caches for Visual Studio Code.",
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
            name: "JetBrains IDE caches",
            summary: "Caches and indexes for IntelliJ, PyCharm, WebStorm and friends, kept per IDE version.",
            category: .otherTools,
            safety: .safe,
            pathPatterns: ["~/Library/Caches/JetBrains"],
            strategy: .removeContents,
            note: "Each IDE rebuilds its index on next launch."
        ),
        CleanupTarget(
            id: "docker-vm-disk",
            name: "Docker VM disk",
            summary: "The virtual disk holding all Docker images, containers and volumes. It only shrinks when Docker itself prunes.",
            category: .otherTools,
            safety: .caution,
            pathPatterns: [
                "~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
                "~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.qcow2",
            ],
            strategy: .manual(instructions: "Run `docker system prune -a` (and optionally `--volumes`) in Terminal, then let Docker Desktop compact the disk.")
        ),
    ]
}
