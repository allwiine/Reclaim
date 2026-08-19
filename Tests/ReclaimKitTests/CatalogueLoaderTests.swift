//
//  CatalogueLoaderTests.swift
//  ReclaimKitTests
//
//  Directory loading against fixtures: deterministic ordering, the
//  files that are (and are not) read, and strict-vs-lenient behavior
//  on a malformed manifest.
//

import Foundation
import Testing
@testable import ReclaimKit

@Suite("Catalogue loader")
struct CatalogueLoaderTests {
    /// Writes `json` at `root/relativePath`, creating directories.
    private func write(_ json: String, to relativePath: String, under root: URL) throws {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    /// A minimal valid target manifest.
    private func targetJSON(id: String, category: String) -> String {
        """
        {
          "id": "\(id)",
          "category": "\(category)",
          "safety": "safe",
          "paths": ["~/Library/Caches/\(id)"],
          "strategy": "removeContents",
          "name": { "en": "\(id) en", "nb": "\(id) nb" },
          "summary": { "en": "Summary.", "nb": "Sammendrag." }
        }
        """
    }

    @Test("Targets load in category display order, then id")
    func ordering() throws {
        try withTemporaryDirectory { root in
            // android precedes xcode alphabetically but follows it in
            // ToolCategory declaration order — this proves the sort.
            try write(targetJSON(id: "b-xcode", category: "xcode"), to: "xcode/b-xcode.json", under: root)
            try write(targetJSON(id: "a-xcode", category: "xcode"), to: "xcode/a-xcode.json", under: root)
            try write(targetJSON(id: "a-android", category: "android"), to: "android/a-android.json", under: root)
            let targets = try CatalogueLoader.loadTargets(from: root, preferring: ["en"])
            #expect(targets.map(\.id) == ["a-xcode", "b-xcode", "a-android"])
        }
    }

    @Test("Only category directories are read — schema/, exclusions/ and README are not targets")
    func onlyCategoryDirectoriesAreRead() throws {
        try withTemporaryDirectory { root in
            try write(targetJSON(id: "real", category: "xcode"), to: "xcode/real.json", under: root)
            try write("{ \"not\": \"a manifest\" }", to: "schema/target.schema.json", under: root)
            try write("# readme", to: "README.md", under: root)
            try write("""
            {"id": "x", "group": "aiTools", "paths": ["~/.x/auth"],
             "reason": {"en": "auth", "nb": "autentisering"}}
            """, to: "exclusions/x.json", under: root)
            let targets = try CatalogueLoader.loadTargets(from: root, preferring: ["en"])
            #expect(targets.map(\.id) == ["real"])
        }
    }

    @Test("Exclusions and reviewed-safe roots load; reviewed-safe-roots.json is not an exclusion")
    func exclusionsAndRoots() throws {
        try withTemporaryDirectory { root in
            try write("""
            {"id": "kube-config", "group": "cloudContainers", "paths": ["~/.kube/config"],
             "reason": {"en": "cluster credentials", "nb": "klyngelegitimasjon"}}
            """, to: "exclusions/kube-config.json", under: root)
            try write("""
            { "~/.npm": "cache and logs; tokens live in ~/.npmrc" }
            """, to: "exclusions/reviewed-safe-roots.json", under: root)
            let exclusions = try CatalogueLoader.loadExclusions(from: root, preferring: ["en"])
            #expect(exclusions.map(\.id) == ["kube-config"])
            #expect(exclusions.first?.reason == "cluster credentials")
            let roots = try CatalogueLoader.loadReviewedSafeRoots(from: root)
            #expect(roots == ["~/.npm"])
        }
    }

    @Test("Strict loading throws and names the offending file")
    func strictLoadingNamesTheFile() throws {
        try withTemporaryDirectory { root in
            try write(targetJSON(id: "good", category: "xcode"), to: "xcode/good.json", under: root)
            try write("{ definitely not json", to: "xcode/broken.json", under: root)
            do {
                _ = try CatalogueLoader.loadTargets(from: root, preferring: ["en"])
                Issue.record("expected strict loading to throw")
            } catch {
                #expect(String(describing: error).contains("broken.json"))
            }
        }
    }

    @Test("Lenient loading skips a malformed file and keeps the rest")
    func lenientLoadingSkips() throws {
        try withTemporaryDirectory { root in
            try write(targetJSON(id: "good", category: "xcode"), to: "xcode/good.json", under: root)
            try write("{ definitely not json", to: "xcode/broken.json", under: root)
            let targets = CatalogueLoader.targetsSkippingFailures(from: root, preferring: ["en"])
            #expect(targets.map(\.id) == ["good"])
        }
    }
}
