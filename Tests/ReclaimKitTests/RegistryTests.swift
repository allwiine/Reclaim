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

    @Test("IDE cache targets declare their owning app for running-app warnings")
    func relatedAppsAreDeclared() {
        let expectations: [String: String] = [
            "xcode-derived-data": "com.apple.dt.Xcode",
            "gradle-caches": "com.google.android.studio",
            "vscode-caches": "com.microsoft.VSCode",
            "claude-desktop-caches": "com.anthropic.claudefordesktop",
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
