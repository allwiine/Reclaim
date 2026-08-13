//
//  ExclusionRegistryTests.swift
//  ReclaimKitTests
//
//  Invariants of the structural exclusion list — the catalogue's
//  mirror image. Break a convention, break the build.
//

import Foundation
import Testing
@testable import ReclaimKit

@Suite("Exclusion registry invariants")
struct ExclusionRegistryTests {
    @Test("Exclusion ids are unique")
    func uniqueIdentifiers() {
        let ids = ExclusionRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Every exclusion has paths and a reason")
    func displayText() {
        for exclusion in ExclusionRegistry.all {
            #expect(!exclusion.paths.isEmpty, "\(exclusion.id) needs at least one path")
            #expect(!exclusion.reason.isEmpty, "\(exclusion.id) needs a reason")
        }
    }

    @Test("Exclusion paths are home-relative or absolute, literal, without trailing slashes")
    func pathShape() {
        for exclusion in ExclusionRegistry.all {
            for path in exclusion.paths {
                #expect(path.hasPrefix("~/") || path.hasPrefix("/"), "\(exclusion.id): \(path)")
                #expect(!path.hasSuffix("/"), "\(exclusion.id): \(path)")
                #expect(!path.contains("*"), "\(exclusion.id): exclusions are literal paths, no globs: \(path)")
            }
        }
    }

    @Test("Exclusion paths are unique across entries")
    func uniquePaths() {
        let paths = ExclusionRegistry.all.flatMap(\.paths)
        #expect(Set(paths).count == paths.count)
    }

    @Test("Every group has entries and a display name")
    func groupsPopulated() {
        for group in ExclusionGroup.allCases {
            #expect(!ExclusionRegistry.entries(in: group).isEmpty, "\(group.rawValue) is empty")
            #expect(!group.displayName.isEmpty, "\(group.rawValue) needs a display name")
        }
    }

    @Test("isProtected guards the path, its contents, and its ancestors")
    func protectionSemantics() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(ExclusionRegistry.isProtected(URL(filePath: "\(home)/.ssh")))
        #expect(ExclusionRegistry.isProtected(URL(filePath: "\(home)/.ssh/id_ed25519")))
        // Disposing the home folder itself would take every exclusion with it.
        #expect(ExclusionRegistry.isProtected(URL(filePath: home)))
        #expect(ExclusionRegistry.isProtected(URL(filePath: "/")))
        // Plain cache content is not protected.
        #expect(!ExclusionRegistry.isProtected(URL(filePath: "\(home)/.npm/_cacache")))
    }
}
