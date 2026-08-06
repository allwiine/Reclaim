//
//  PathResolverTests.swift
//  ReclaimKitTests
//

import Foundation
import Testing
@testable import ReclaimKit

@Suite("Path resolution")
struct PathResolverTests {
    @Test("Tilde expands against the injected home directory")
    func tildeExpansion() throws {
        try withTemporaryDirectory { home in
            let caches = home.appending(path: "Library/Caches")
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)

            let resolver = PathResolver(home: home)
            let resolved = resolver.resolve("~/Library/Caches")

            #expect(resolved.map(\.path) == [caches.path])
        }
    }

    @Test("Globs match multiple versioned directories")
    func globMatching() throws {
        try withTemporaryDirectory { home in
            let google = home.appending(path: "Library/Caches/Google")
            for name in ["AndroidStudio2024.1", "AndroidStudio2025.2", "Chrome"] {
                try FileManager.default.createDirectory(
                    at: google.appending(path: name),
                    withIntermediateDirectories: true
                )
            }

            let resolver = PathResolver(home: home)
            let resolved = resolver.resolve("~/Library/Caches/Google/AndroidStudio*")

            #expect(resolved.count == 2)
            #expect(resolved.allSatisfy { $0.lastPathComponent.hasPrefix("AndroidStudio") })
            // Deterministic order for stable UI and tests.
            #expect(resolved.map(\.path) == resolved.map(\.path).sorted())
        }
    }

    @Test("Non-existent paths resolve to nothing")
    func missingPaths() throws {
        try withTemporaryDirectory { home in
            let resolver = PathResolver(home: home)
            #expect(resolver.resolve("~/Definitely/Not/Here").isEmpty)
            #expect(resolver.resolve("~/Nope*").isEmpty)
        }
    }

    @Test("resolveAll concatenates matches across patterns")
    func resolveAllConcatenates() throws {
        try withTemporaryDirectory { home in
            let a = home.appending(path: "a")
            let b = home.appending(path: "b")
            try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)

            let resolver = PathResolver(home: home)
            let resolved = resolver.resolveAll(["~/a", "~/missing", "~/b"])

            #expect(resolved.map(\.lastPathComponent) == ["a", "b"])
        }
    }

    @Test("Glob matching escapes regex metacharacters")
    func globEscaping() {
        #expect(PathResolver.matches(name: "foo.bar", glob: "foo.bar"))
        #expect(!PathResolver.matches(name: "fooXbar", glob: "foo.bar"))
        #expect(PathResolver.matches(name: "AndroidStudio2025.2", glob: "AndroidStudio*"))
        #expect(!PathResolver.matches(name: "Chrome", glob: "AndroidStudio*"))
        #expect(PathResolver.matches(name: "anything", glob: "*"))
    }
}
