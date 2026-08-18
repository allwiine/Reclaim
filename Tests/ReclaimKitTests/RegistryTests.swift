//
//  RegistryTests.swift
//  ReclaimKitTests
//
//  Invariants of the target catalogue. These tests are what makes the
//  registry safe to extend: break a convention, break the build.
//

import Foundation
import Testing
@testable import ReclaimKit

@Suite("Target registry invariants")
struct RegistryTests {
    @Test("Target ids are unique")
    func uniqueIdentifiers() {
        let ids = TargetRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Every target has display text")
    func displayText() {
        for target in TargetRegistry.all {
            #expect(!target.name.isEmpty, "\(target.id) needs a name")
            #expect(!target.summary.isEmpty, "\(target.id) needs a summary")
        }
    }

    @Test("Path patterns are home-relative or absolute, without trailing slashes")
    func patternShape() {
        for target in TargetRegistry.all {
            for pattern in target.pathPatterns {
                #expect(
                    pattern.hasPrefix("~/") || pattern.hasPrefix("/"),
                    "\(target.id): \(pattern)"
                )
                #expect(!pattern.hasSuffix("/"), "\(target.id): \(pattern)")
            }
        }
    }

    @Test("Only command targets may omit paths")
    func pathlessTargetsAreCommands() {
        for target in TargetRegistry.all where target.pathPatterns.isEmpty {
            guard case .command = target.strategy else {
                Issue.record("\(target.id) has no paths but is not command-based")
                continue
            }
        }
    }

    @Test("Manual targets are never rated Safe")
    func manualTargetsAreNeverSafe() {
        // The overview's category ring assumes safe + review + projects
        // sum to the total, which holds only while no `.manual` target is
        // rated `.safe` (a safe manual target would fall in neither the
        // safe-and-cleanable bucket nor the review bucket).
        for target in TargetRegistry.all {
            if case .manual = target.strategy {
                #expect(
                    target.safety != .safe,
                    "\(target.id) is manual and rated Safe — it would break the overview ring sum"
                )
            }
        }
    }

    @Test("No target pattern collides with a structural exclusion")
    func exclusionsAreRespected() {
        for target in TargetRegistry.all {
            for pattern in target.pathPatterns {
                for exclusion in ExclusionRegistry.all {
                    for protectedPath in exclusion.paths {
                        #expect(
                            pattern != protectedPath,
                            "\(target.id) targets protected \(protectedPath)"
                        )
                        #expect(
                            !pattern.hasPrefix(protectedPath + "/"),
                            "\(target.id) targets inside protected \(protectedPath)"
                        )
                        #expect(
                            !protectedPath.hasPrefix(pattern + "/"),
                            "\(target.id) pattern \(pattern) would dispose an ancestor of protected \(protectedPath)"
                        )
                    }
                }
            }
        }
    }

    @Test("Every category has at least one target", arguments: ToolCategory.allCases)
    func categoryPopulated(category: ToolCategory) {
        #expect(!TargetRegistry.targets(in: category).isEmpty, "\(category) has no targets")
    }

    @Test("IDE cache targets declare their owning app for running-app warnings")
    func relatedAppsAreDeclared() {
        let expectations: [String: String] = [
            "xcode-derived-data": "com.apple.dt.Xcode",
            "gradle-caches": "com.google.android.studio",
            "nuget-packages": "com.jetbrains.rider",
            "vscode-caches": "com.microsoft.VSCode",
            "claude-desktop-caches": "com.anthropic.claudefordesktop",
            "rancher-desktop-caches": "io.rancherdesktop.app",
            "unity-caches": "com.unity3d.UnityEditor5.x",
            "godot-caches": "org.godotengine.godot",
            "zed-caches": "dev.zed.Zed",
            "cursor-caches": "com.todesktop.230313mzl4w4u92",
            "windsurf-caches": "com.exafunction.windsurf",
            "antigravity-caches": "com.google.antigravity",
        ]
        for (id, bundleID) in expectations {
            let target = TargetRegistry.all.first { $0.id == id }
            #expect(
                target?.relatedAppBundleIDs.contains(bundleID) == true,
                "\(id) should declare \(bundleID)"
            )
        }
    }

    @Test("Categories cover every target", arguments: ToolCategory.allCases)
    func categoryLookupIsConsistent(category: ToolCategory) {
        let viaLookup = TargetRegistry.targets(in: category).map(\.id)
        let viaFilter = TargetRegistry.all.filter { $0.category == category }.map(\.id)
        #expect(viaLookup == viaFilter)
    }

    @Test("Every root a target reaches into is reviewed-safe or carries an exclusion")
    func rootsAreReviewed() {
        var roots: Set<String> = []
        for target in TargetRegistry.all {
            for pattern in target.pathPatterns {
                if let root = Self.sensitiveRoot(of: pattern) {
                    roots.insert(root)
                }
            }
        }

        let exclusionPaths = ExclusionRegistry.all.flatMap(\.paths)
        for root in roots.sorted() {
            let covered = exclusionPaths.contains { $0 == root || $0.hasPrefix(root + "/") }
            let reviewed = ExclusionRegistry.reviewedSafeRoots.contains(root)
            #expect(
                covered || reviewed,
                """
                \(root): a target reaches into this folder. Register an exclusion \
                for the credentials/settings that live beside the targeted paths, \
                or add the root to ExclusionRegistry.reviewedSafeRoots if nothing \
                sensitive lives there.
                """
            )
            #expect(
                !(covered && reviewed),
                "\(root) is declared reviewed-safe but contains exclusions: remove it from reviewedSafeRoots"
            )
        }

        // The safe list must not outlive the targets that justified it.
        let stale = ExclusionRegistry.reviewedSafeRoots.subtracting(roots)
        #expect(stale.isEmpty, "reviewedSafeRoots no longer reached by any target: \(stale.sorted())")
    }

    /// Shared folders where many tools keep their data side by side.
    /// Roots under these are derived one component deeper, so each
    /// tool's folder gets its own review decision. Longest prefix first.
    private static let umbrellaRoots = [
        "~/.local/share", "~/.local/state", "~/.local", "~/.cache", "~/.config",
    ]

    /// The reviewable root of a pattern: `~/.<name>`,
    /// `~/Library/Application Support/<Name>`, or one component below an
    /// umbrella folder (`~/.cache/<tool>`), but only when the pattern
    /// reaches *deeper* than the root itself. A target that claims a
    /// whole folder (`~/.ccache`) asserts the folder is wholly
    /// disposable; a target that reaches inside one (`~/.codex/sessions`)
    /// leaves siblings worth reviewing.
    private static func sensitiveRoot(of pattern: String) -> String? {
        for umbrella in umbrellaRoots where pattern.hasPrefix(umbrella + "/") {
            let rest = pattern.dropFirst(umbrella.count + 1)
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            return umbrella + "/" + rest[..<slash]
        }
        let appSupport = "~/Library/Application Support/"
        if pattern.hasPrefix(appSupport) {
            let rest = pattern.dropFirst(appSupport.count)
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            return appSupport + rest[..<slash]
        }
        if pattern.hasPrefix("~/.") {
            let rest = pattern.dropFirst(2)
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            return "~/" + rest[..<slash]
        }
        return nil
    }
}
