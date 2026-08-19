//
//  TargetRegistry.swift
//  ReclaimKit
//
//  The built-in target catalogue. The data lives in JSON manifests
//  under Sources/ReclaimKit/Catalogue/ — one file per target, bundled
//  as a resource and loaded once by CatalogueLoader. To support a new
//  tool, add one manifest there (see docs/CATALOGUE.md); no code
//  changes required. Conventions are enforced by RegistryTests and
//  CatalogueConventionTests.
//

import Foundation

/// Namespace for the built-in target catalogue.
public enum TargetRegistry {
    /// All targets, in category display order, then by id.
    public static let all: [CleanupTarget] = CatalogueLoader.bundledTargets

    /// Convenience: targets grouped by category, preserving order.
    public static func targets(in category: ToolCategory) -> [CleanupTarget] {
        all.filter { $0.category == category }
    }
}
