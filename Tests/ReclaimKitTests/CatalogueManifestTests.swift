//
//  CatalogueManifestTests.swift
//  ReclaimKitTests
//
//  The manifest DTOs: JSON decoding, locale resolution, and mapping
//  onto the domain types, including every rejection path.
//

import Foundation
import Testing
@testable import ReclaimKit

@Suite("Catalogue manifest models")
struct CatalogueManifestTests {
    private func decodeTarget(_ json: String) throws -> TargetManifest {
        try JSONDecoder().decode(TargetManifest.self, from: Data(json.utf8))
    }

    @Test("A path target decodes and maps onto CleanupTarget")
    func pathTarget() throws {
        let manifest = try decodeTarget("""
        {
          "$schema": "../schema/target.schema.json",
          "id": "xcode-derived-data",
          "category": "xcode",
          "safety": "safe",
          "paths": ["~/Library/Developer/Xcode/DerivedData"],
          "strategy": "removeContents",
          "relatedApps": ["com.apple.dt.Xcode"],
          "name": { "en": "Derived data", "nb": "Avledede data" },
          "summary": { "en": "Build products.", "nb": "Byggprodukter." }
        }
        """)
        let target = try manifest.cleanupTarget(preferring: ["en"], file: "xcode-derived-data.json")
        #expect(target.id == "xcode-derived-data")
        #expect(target.category == .xcode)
        #expect(target.safety == .safe)
        #expect(target.pathPatterns == ["~/Library/Developer/Xcode/DerivedData"])
        #expect(target.strategy == .removeContents)
        #expect(target.name == "Derived data")
        #expect(target.summary == "Build products.")
        #expect(target.note == nil)
        #expect(target.relatedAppBundleIDs == ["com.apple.dt.Xcode"])
    }

    @Test("Norwegian is picked when preferred; English is the fallback")
    func localeResolution() {
        let text = LocalizedText(values: ["en": "English", "nb": "Norsk"])
        #expect(text.resolved(preferring: ["nb", "en"]) == "Norsk")
        #expect(text.resolved(preferring: ["en"]) == "English")
        #expect(text.resolved(preferring: ["de", "en"]) == "English")
        #expect(text.resolved(preferring: ["de"]) == "English", "unknown language falls back to en")
    }

    @Test("A command target maps its CommandSpec")
    func commandTarget() throws {
        let manifest = try decodeTarget("""
        {
          "id": "xcode-unavailable-simulators",
          "category": "xcode",
          "safety": "safe",
          "strategy": "command",
          "command": {
            "executable": "/usr/bin/xcrun",
            "arguments": ["simctl", "delete", "unavailable"],
            "display": "xcrun simctl delete unavailable",
            "availabilityProbe": "~/Library/Developer/CoreSimulator"
          },
          "name": { "en": "Unavailable simulators", "nb": "Utilgjengelige simulatorer" },
          "summary": { "en": "S.", "nb": "S." }
        }
        """)
        let target = try manifest.cleanupTarget(preferring: ["en"], file: "f.json")
        #expect(target.pathPatterns.isEmpty)
        #expect(target.strategy == .command(CommandSpec(
            executablePath: "/usr/bin/xcrun",
            arguments: ["simctl", "delete", "unavailable"],
            displayCommand: "xcrun simctl delete unavailable",
            availabilityProbePattern: "~/Library/Developer/CoreSimulator"
        )))
    }

    @Test("A manual target resolves its instructions")
    func manualTarget() throws {
        let manifest = try decodeTarget("""
        {
          "id": "go-module-cache",
          "category": "packageManagers",
          "safety": "caution",
          "paths": ["~/go/pkg/mod"],
          "strategy": "manual",
          "instructions": { "en": "Run `go clean -modcache`.", "nb": "Kjør `go clean -modcache`." },
          "name": { "en": "Go module cache", "nb": "Go-modulmellomlager" },
          "summary": { "en": "S.", "nb": "S." }
        }
        """)
        let target = try manifest.cleanupTarget(preferring: ["nb", "en"], file: "f.json")
        #expect(target.strategy == .manual(instructions: "Kjør `go clean -modcache`."))
    }

    @Test("Strategy/companion mismatches and unknown enum values are rejected")
    func rejections() throws {
        // Each entry: (invalid manifest JSON, expected reason fragment).
        let cases: [(String, String)] = [
            // command strategy without a command object
            ("""
            {"id": "a", "category": "xcode", "safety": "safe", "strategy": "command",
             "name": {"en": "A", "nb": "A"}, "summary": {"en": "S.", "nb": "S."}}
            """, "command"),
            // manual strategy without instructions
            ("""
            {"id": "a", "category": "xcode", "safety": "safe", "paths": ["~/x"], "strategy": "manual",
             "name": {"en": "A", "nb": "A"}, "summary": {"en": "S.", "nb": "S."}}
            """, "manual"),
            // removeContents with a stray command object
            ("""
            {"id": "a", "category": "xcode", "safety": "safe", "paths": ["~/x"], "strategy": "removeContents",
             "command": {"executable": "/x", "arguments": [], "display": "x"},
             "name": {"en": "A", "nb": "A"}, "summary": {"en": "S.", "nb": "S."}}
            """, "removeContents"),
            // unknown category
            ("""
            {"id": "a", "category": "nope", "safety": "safe", "paths": ["~/x"], "strategy": "removeContents",
             "name": {"en": "A", "nb": "A"}, "summary": {"en": "S.", "nb": "S."}}
            """, "category"),
            // unknown safety
            ("""
            {"id": "a", "category": "xcode", "safety": "mild", "paths": ["~/x"], "strategy": "removeContents",
             "name": {"en": "A", "nb": "A"}, "summary": {"en": "S.", "nb": "S."}}
            """, "safety"),
            // unknown strategy
            ("""
            {"id": "a", "category": "xcode", "safety": "safe", "paths": ["~/x"], "strategy": "obliterate",
             "name": {"en": "A", "nb": "A"}, "summary": {"en": "S.", "nb": "S."}}
            """, "strategy"),
        ]
        for (json, fragment) in cases {
            let manifest = try decodeTarget(json)
            do {
                _ = try manifest.cleanupTarget(preferring: ["en"], file: "f.json")
                Issue.record("expected rejection for fragment '\(fragment)'")
            } catch {
                #expect(String(describing: error).contains(fragment),
                        "error for '\(fragment)' was: \(error)")
            }
        }
    }

    @Test("An exclusion manifest maps onto StructuralExclusion")
    func exclusion() throws {
        let manifest = try JSONDecoder().decode(ExclusionManifest.self, from: Data("""
        {
          "$schema": "../schema/exclusion.schema.json",
          "id": "claude-auth",
          "group": "claudeCode",
          "paths": ["~/.claude.json"],
          "reason": { "en": "auth & app state", "nb": "autentisering og apptilstand" }
        }
        """.utf8))
        let exclusion = try manifest.structuralExclusion(preferring: ["en"], file: "claude-auth.json")
        #expect(exclusion.id == "claude-auth")
        #expect(exclusion.group == .claudeCode)
        #expect(exclusion.paths == ["~/.claude.json"])
        #expect(exclusion.reason == "auth & app state")

        let bad = try JSONDecoder().decode(ExclusionManifest.self, from: Data("""
        {"id": "x", "group": "nope", "paths": ["~/x"], "reason": {"en": "r", "nb": "r"}}
        """.utf8))
        #expect(throws: (any Error).self) {
            _ = try bad.structuralExclusion(preferring: ["en"], file: "x.json")
        }
    }
}
