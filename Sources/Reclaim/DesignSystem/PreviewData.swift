//
//  PreviewData.swift
//  Reclaim
//
//  Canned models for SwiftUI previews — realistic sizes over the real
//  registry, no filesystem access, ephemeral defaults.
//

#if DEBUG

import Foundation
import ReclaimAppCore
import ReclaimKit

@MainActor
enum PreviewData {
    /// Gigabytes → bytes, for readable fixture tables.
    private static func gb(_ value: Double) -> Int64 { Int64(value * 1_000_000_000) }

    private static let sizes: [String: Double] = [
        "xcode-derived-data": 34.2,
        "xcode-device-support": 18.6,
        "xcode-simulator-caches": 11.9,
        "xcode-previews": 6.1,
        "xcode-archives": 9.4,
        "xcode-caches": 2.1,
        "gradle-caches": 16.3,
        "gradle-wrapper-dists": 4.7,
        "android-studio-caches": 3.2,
        "android-system-images": 12.8,
        "android-avds": 4.8,
        "claude-code-cli-caches": 2.4,
        "claude-code-scratch": 0.9,
        "claude-code-transcripts": 1.3,
        "claude-desktop-caches": 1.1,
        "ollama-models": 14.7,
        "huggingface-cache": 6.2,
        "lmstudio-models": 2.0,
        "homebrew-cache": 5.6,
        "npm-cache": 3.4,
        "pnpm-store": 2.9,
        "yarn-cache": 1.6,
        "pip-cache": 2.2,
        "uv-cache": 1.4,
        "cocoapods-cache": 1.8,
        "spm-cache": 2.1,
        "cargo-registry": 1.1,
        "go-module-cache": 4.3,
        "vscode-caches": 3.1,
        "jetbrains-caches": 2.6,
        "docker-vm-disk": 31.4,
    ]

    private static let sampleHistory: [CleanHistoryEntry] = [
        CleanHistoryEntry(
            date: .now.addingTimeInterval(-25 * 86_400),
            targetNames: ["Derived data", "Simulator caches", "npm cache"],
            itemsRemoved: 31, reclaimedBytes: 41_200_000_000
        ),
        CleanHistoryEntry(
            date: .now.addingTimeInterval(-39 * 86_400),
            targetNames: ["Gradle caches", "Gradle wrapper distributions"],
            itemsRemoved: 12, reclaimedBytes: 18_900_000_000
        ),
        CleanHistoryEntry(
            date: .now.addingTimeInterval(-53 * 86_400),
            targetNames: ["Derived data", "Device support files", "Homebrew downloads"],
            itemsRemoved: 44, reclaimedBytes: 52_600_000_000
        ),
        CleanHistoryEntry(
            date: .now.addingTimeInterval(-68 * 86_400),
            targetNames: ["Ollama models"],
            itemsRemoved: 2, reclaimedBytes: 11_400_000_000
        ),
        CleanHistoryEntry(
            date: .now.addingTimeInterval(-87 * 86_400),
            targetNames: ["Derived data", "SwiftUI Previews data", "pip cache"],
            itemsRemoved: 26, reclaimedBytes: 27_800_000_000
        ),
    ]

    /// A model that looks freshly launched: no scan yet.
    static func idle() -> AppModel {
        makeModel()
    }

    /// A model with a completed scan and the safe items preselected.
    static func scanned() -> AppModel {
        let model = makeModel()
        var statuses: [CleanupTarget.ID: TargetStatus] = [:]
        for target in model.targets {
            if let size = sizes[target.id] {
                let root = URL(filePath: "/Users/dev/Library/\(target.id)")
                statuses[target.id] = .measured(
                    DiskMeasurement(bytes: gb(size), fileCount: Int(size * 800)),
                    resolvedPaths: [root],
                    cleanupPaths: target.strategy.isCleanable ? [
                        root.appending(path: "a"), root.appending(path: "b"),
                    ] : []
                )
            } else if case .command = target.strategy {
                statuses[target.id] = .unmeasurable
            } else {
                statuses[target.id] = .notInstalled
            }
        }
        let selection = Set(model.targets.filter {
            $0.safety == .safe && $0.strategy.isCleanable && sizes[$0.id] != nil
        }.map(\.id))

        var breakdowns: [CleanupTarget.ID: [BreakdownEntry]] = [:]
        breakdowns["xcode-derived-data"] = [
            BreakdownEntry(name: "Monarch-fkzqwlbhdtxrmvexz", bytes: gb(11.4)),
            BreakdownEntry(name: "ledger-ios-gxbtpqnnvzdlma", bytes: gb(8.9)),
            BreakdownEntry(name: "Aperture-dqrmtnkzzwsple", bytes: gb(6.2)),
            BreakdownEntry(name: "scratchpad-bxlmnvvrqtd", bytes: gb(4.1)),
            BreakdownEntry(name: "+ 23 more items", bytes: gb(3.6), itemCount: 23),
        ]

        model.seedForPreview(
            statuses: statuses,
            selection: selection,
            history: sampleHistory,
            breakdowns: breakdowns,
            volumeSpace: VolumeSpace(
                totalBytes: 1_000_000_000_000, availableBytes: 258_000_000_000
            )
        )
        return model
    }

    /// Scanned, plus a finished clean pass for the Done screen.
    static func cleaned() -> AppModel {
        let model = scanned()
        var summary = CleanSummary(disposal: .trash)
        summary.itemsRemoved = 31
        summary.cleanedTargets = 4
        summary.reclaimedBytes = gb(64.8)
        summary.cleaned = [
            .init(id: "xcode-derived-data", name: "Derived data", category: .xcode, bytesFreed: gb(34.2)),
            .init(id: "xcode-device-support", name: "Device support files", category: .xcode, bytesFreed: gb(18.6)),
            .init(id: "gradle-caches", name: "Gradle caches", category: .android, bytesFreed: gb(8.6)),
            .init(id: "npm-cache", name: "npm cache", category: .packageManagers, bytesFreed: gb(3.4)),
        ]
        model.lastCleanSummary = summary
        return model
    }

    private static func makeModel() -> AppModel {
        AppModel(
            defaults: UserDefaults(suiteName: "previews-\(UUID().uuidString)")!,
            scanExecutor: { _ in .notInstalled },
            cleanExecutor: { _, _, _ in CleanOutcome() },
            breakdownExecutor: { _ in nil },
            fullDiskAccessProbe: { true },
            volumeProbe: { nil },
            historyStore: CleanHistoryStore(
                fileURL: FileManager.default.temporaryDirectory
                    .appending(path: "previews-\(UUID().uuidString).json")
            )
        )
    }
}

#endif
