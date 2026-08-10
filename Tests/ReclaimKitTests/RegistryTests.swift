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

    @Test("Claude Code auth, settings and plugins are never registered")
    func claudeConfigIsProtected() {
        for target in TargetRegistry.all {
            for pattern in target.pathPatterns {
                #expect(pattern != "~/.claude", "\(target.id) must not target the whole ~/.claude folder")
                #expect(!pattern.contains(".claude.json"), "\(target.id) must not touch auth")
                #expect(!pattern.contains(".claude/settings"), "\(target.id) must not touch settings")
                #expect(!pattern.contains(".claude/plugins"), "\(target.id) must not touch plugins")
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

    @Test(".NET credentials and installed tools are never registered")
    func dotNetUserDataIsProtected() {
        for target in TargetRegistry.all {
            for pattern in target.pathPatterns {
                #expect(!pattern.contains(".aspnet"), "\(target.id) must not touch dev certs or DataProtection keys")
                #expect(pattern != "~/.dotnet", "\(target.id) must not target the whole ~/.dotnet folder")
                #expect(!pattern.contains(".dotnet/tools"), "\(target.id) must not touch installed global tools")
                #expect(!pattern.contains(".nuget/plugins"), "\(target.id) must not touch credential providers")
                #expect(pattern != "~/.nuget", "\(target.id) must not target the whole ~/.nuget folder")
            }
        }
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
}
