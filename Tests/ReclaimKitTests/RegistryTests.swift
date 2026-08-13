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

    @Test("The .NET category has targets")
    func dotNetCategoryPopulated() {
        #expect(!TargetRegistry.targets(in: .dotNet).isEmpty)
    }

    @Test("The containers category has targets")
    func containersCategoryPopulated() {
        #expect(!TargetRegistry.targets(in: .containers).isEmpty)
    }

    @Test("The JVM category has targets")
    func jvmCategoryPopulated() {
        #expect(!TargetRegistry.targets(in: .jvm).isEmpty)
    }

    @Test("The web tools category has targets")
    func webToolsCategoryPopulated() {
        #expect(!TargetRegistry.targets(in: .webTools).isEmpty)
    }

    @Test("The cloud & DevOps category has targets")
    func cloudDevOpsCategoryPopulated() {
        #expect(!TargetRegistry.targets(in: .cloudDevOps).isEmpty)
    }

    @Test("The game engines category has targets")
    func gameEnginesCategoryPopulated() {
        #expect(!TargetRegistry.targets(in: .gameEngines).isEmpty)
    }

    @Test("The embedded category has targets")
    func embeddedCategoryPopulated() {
        #expect(!TargetRegistry.targets(in: .embedded).isEmpty)
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

    /// The reviewable root of a pattern: `~/.<name>` or
    /// `~/Library/Application Support/<Name>`, but only when the
    /// pattern reaches *deeper* than the root itself. A target that
    /// claims a whole folder (`~/.ccache`) asserts the folder is
    /// wholly disposable; a target that reaches inside one
    /// (`~/.codex/sessions`) leaves siblings worth reviewing.
    private static func sensitiveRoot(of pattern: String) -> String? {
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
