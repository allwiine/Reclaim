//
//  MigrationEquivalenceTests.swift
//  ReclaimKitTests
//
//  TEMPORARY — deleted together with the legacy registry literals.
//  Proves the loaded JSON catalogue equals the Swift registries
//  field-for-field, so the literals can be removed with confidence.
//

import Foundation
import Testing
@testable import ReclaimKit

@Suite("Migration equivalence (temporary)")
struct MigrationEquivalenceTests {
    @Test("Loaded targets equal the legacy registry field-for-field")
    func targetsMatch() throws {
        let root = try #require(CatalogueLoader.bundledCatalogueURL)
        let loaded = try CatalogueLoader.loadTargets(
            from: root, preferring: CatalogueLoader.preferredLanguages)
        let legacy = Dictionary(uniqueKeysWithValues: TargetRegistry.all.map { ($0.id, $0) })
        #expect(loaded.count == legacy.count)
        for target in loaded {
            let original = try #require(legacy[target.id], "\(target.id) is not in the legacy registry")
            #expect(target.name == original.name, "\(target.id) name")
            #expect(target.summary == original.summary, "\(target.id) summary")
            #expect(target.category == original.category, "\(target.id) category")
            #expect(target.safety == original.safety, "\(target.id) safety")
            #expect(target.pathPatterns == original.pathPatterns, "\(target.id) paths")
            #expect(target.strategy == original.strategy, "\(target.id) strategy")
            #expect(target.note == original.note, "\(target.id) note")
            #expect(target.relatedAppBundleIDs == original.relatedAppBundleIDs, "\(target.id) relatedApps")
        }
    }

    @Test("Loaded exclusions equal the legacy registry field-for-field")
    func exclusionsMatch() throws {
        let root = try #require(CatalogueLoader.bundledCatalogueURL)
        let loaded = try CatalogueLoader.loadExclusions(
            from: root, preferring: CatalogueLoader.preferredLanguages)
        let legacy = Dictionary(uniqueKeysWithValues: ExclusionRegistry.all.map { ($0.id, $0) })
        #expect(loaded.count == legacy.count)
        for exclusion in loaded {
            let original = try #require(legacy[exclusion.id], "\(exclusion.id) is not in the legacy registry")
            #expect(exclusion.paths == original.paths, "\(exclusion.id) paths")
            #expect(exclusion.group == original.group, "\(exclusion.id) group")
            #expect(exclusion.reason == original.reason, "\(exclusion.id) reason")
        }
    }

    @Test("Loaded reviewed-safe roots equal the legacy set")
    func reviewedSafeRootsMatch() throws {
        let root = try #require(CatalogueLoader.bundledCatalogueURL)
        let loaded = try CatalogueLoader.loadReviewedSafeRoots(from: root)
        #expect(loaded == ExclusionRegistry.reviewedSafeRoots)
    }
}
