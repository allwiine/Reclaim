//
//  ArtifactCatalogTests.swift
//  ReclaimKitTests
//
//  The artifact catalogue's contract — what makes "just add a kind" safe.
//

import Foundation
import Testing
import ReclaimKit

@Suite("Artifact catalogue")
struct ArtifactCatalogTests {
    @Test("Kind ids are unique and non-empty")
    func uniqueIdentifiers() {
        let ids = ArtifactCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { !$0.isEmpty })
        #expect(ArtifactCatalog.all.allSatisfy { !$0.name.isEmpty })
    }

    @Test("No directory name is claimed by two kinds")
    func directoryNamesDoNotOverlap() {
        let names = ArtifactCatalog.all.flatMap(\.directoryNames)
        #expect(Set(names).count == names.count)
    }

    @Test("Ambiguous directory names always demand proof")
    func ambiguousNamesNeedProof() {
        // Generic names that legitimately hold user content elsewhere.
        let ambiguous: Set<String> = ["build", "dist", "target", "out"]
        for kind in ArtifactCatalog.all
        where kind.directoryNames.contains(where: ambiguous.contains) {
            #expect(kind.proof != .nameAlone, "\(kind.id) claims a generic name without proof")
        }
    }

    @Test("The catalogue can never touch Claude Code user data")
    func claudeDataStructurallyExcluded() {
        for kind in ArtifactCatalog.all {
            #expect(!kind.directoryNames.contains(".claude"))
            #expect(kind.nestedChild != ".claude")
        }
    }

    @Test("Project markers are exactly the sibling-proof names")
    func projectMarkers() {
        #expect(ArtifactCatalog.projectMarkers.contains("package.json"))
        #expect(ArtifactCatalog.projectMarkers.contains("Cargo.toml"))
        #expect(ArtifactCatalog.projectMarkers.contains("Package.swift"))
        #expect(!ArtifactCatalog.projectMarkers.contains("pyvenv.cfg"))
    }

    @Test("Matching honors sibling proof")
    func matchingHonorsProof() {
        #expect(ArtifactCatalog.match(
            directoryName: "node_modules", siblingNames: ["package.json"]
        )?.id == "node-modules")
        #expect(ArtifactCatalog.match(
            directoryName: "node_modules", siblingNames: ["README.md"]
        ) == nil)
        #expect(ArtifactCatalog.match(
            directoryName: "dist", siblingNames: ["Cargo.toml"]
        ) == nil)
        #expect(ArtifactCatalog.match(
            directoryName: "__pycache__", siblingNames: []
        )?.id == "python-cache")
        #expect(ArtifactCatalog.match(
            directoryName: "build", siblingNames: ["build.gradle.kts"]
        )?.id == "gradle-build")
    }
}
