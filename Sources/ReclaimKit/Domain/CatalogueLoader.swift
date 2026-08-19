//
//  CatalogueLoader.swift
//  ReclaimKit
//
//  Materializes the domain catalogue from the JSON manifests bundled
//  under Catalogue/. Strict loading (throws on the first invalid file)
//  backs the test suite, which is what actually gates a bad manifest
//  out of a release. The lenient variants back the app at runtime,
//  where a malformed file — impossible unless the bundle is corrupt —
//  is logged as a fault and skipped, never fatal.
//

import Foundation
import os

enum CatalogueLoader {
    // MARK: - Bundle access

    /// The catalogue directory inside the module bundle
    /// (`.copy("Catalogue")` in Package.swift preserves the layout).
    static var bundledCatalogueURL: URL? {
        Bundle.module.url(forResource: "Catalogue", withExtension: nil)
    }

    /// Language codes for resolving localized text: the module
    /// bundle's preferred localizations (which honor the per-app
    /// language override in System Settings), restricted to catalogue
    /// locales, with English as the final fallback.
    static var preferredLanguages: [String] {
        Bundle.module.preferredLocalizations.filter { CatalogueLocales.supported.contains($0) }
            + [CatalogueLocales.fallback]
    }

    // MARK: - The bundled catalogue (what the registries serve)

    static let bundledTargets: [CleanupTarget] = {
        guard let root = bundledCatalogueURL else {
            Log.catalogue.fault("Catalogue directory missing from ReclaimKit resources")
            return []
        }
        return targetsSkippingFailures(from: root, preferring: preferredLanguages)
    }()

    static let bundledExclusions: [StructuralExclusion] = {
        guard let root = bundledCatalogueURL else {
            Log.catalogue.fault("Catalogue directory missing from ReclaimKit resources")
            return []
        }
        return exclusionsSkippingFailures(from: root, preferring: preferredLanguages)
    }()

    static let bundledReviewedSafeRoots: Set<String> = {
        guard let root = bundledCatalogueURL else {
            Log.catalogue.fault("Catalogue directory missing from ReclaimKit resources")
            return []
        }
        return reviewedSafeRootsSkippingFailures(from: root)
    }()

    // MARK: - Strict loading (tests and CI — throws on the first bad file)

    static func loadTargets(
        from catalogueRoot: URL, preferring languages: [String]
    ) throws -> [CleanupTarget] {
        try manifestFiles(inCategoryDirectoriesOf: catalogueRoot)
            .map { url in
                try decode(TargetManifest.self, at: url)
                    .cleanupTarget(preferring: languages, file: url.lastPathComponent)
            }
            .sorted(by: displayOrder)
    }

    static func loadExclusions(
        from catalogueRoot: URL, preferring languages: [String]
    ) throws -> [StructuralExclusion] {
        try exclusionFiles(in: catalogueRoot)
            .map { url in
                try decode(ExclusionManifest.self, at: url)
                    .structuralExclusion(preferring: languages, file: url.lastPathComponent)
            }
            .sorted { (groupOrder[$0.group] ?? .max, $0.id) < (groupOrder[$1.group] ?? .max, $1.id) }
    }

    static func loadReviewedSafeRoots(from catalogueRoot: URL) throws -> Set<String> {
        // Shape: { "<tilde-form root>": "<review rationale>", … }.
        // The rationale is maintainer-facing documentation; only the
        // keys become domain data.
        Set(try decode([String: String].self, at: reviewedSafeRootsURL(in: catalogueRoot)).keys)
    }

    // MARK: - Lenient loading (app runtime — logs and skips, never fatal)

    static func targetsSkippingFailures(
        from catalogueRoot: URL, preferring languages: [String]
    ) -> [CleanupTarget] {
        let files = (try? manifestFiles(inCategoryDirectoriesOf: catalogueRoot)) ?? []
        return files.compactMap { url in
            do {
                return try decode(TargetManifest.self, at: url)
                    .cleanupTarget(preferring: languages, file: url.lastPathComponent)
            } catch {
                Log.catalogue.fault("Skipping target manifest \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
                return nil
            }
        }
        .sorted(by: displayOrder)
    }

    static func exclusionsSkippingFailures(
        from catalogueRoot: URL, preferring languages: [String]
    ) -> [StructuralExclusion] {
        let files = (try? exclusionFiles(in: catalogueRoot)) ?? []
        return files.compactMap { url in
            do {
                return try decode(ExclusionManifest.self, at: url)
                    .structuralExclusion(preferring: languages, file: url.lastPathComponent)
            } catch {
                Log.catalogue.fault("Skipping exclusion manifest \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
                return nil
            }
        }
        .sorted { (groupOrder[$0.group] ?? .max, $0.id) < (groupOrder[$1.group] ?? .max, $1.id) }
    }

    static func reviewedSafeRootsSkippingFailures(from catalogueRoot: URL) -> Set<String> {
        do {
            return try loadReviewedSafeRoots(from: catalogueRoot)
        } catch {
            Log.catalogue.fault("Skipping reviewed-safe-roots.json: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    // MARK: - File discovery

    /// `<root>/<category rawValue>/*.json` for every ToolCategory.
    /// Only category directories are read, so `schema/`, `exclusions/`
    /// and README.md are naturally never treated as targets.
    private static func manifestFiles(inCategoryDirectoriesOf root: URL) throws -> [URL] {
        try ToolCategory.allCases.flatMap { category in
            try jsonFiles(in: root.appending(path: category.rawValue))
        }
    }

    private static func exclusionFiles(in root: URL) throws -> [URL] {
        try jsonFiles(in: root.appending(path: "exclusions"))
            .filter { $0.lastPathComponent != "reviewed-safe-roots.json" }
    }

    private static func reviewedSafeRootsURL(in root: URL) -> URL {
        root.appending(path: "exclusions/reviewed-safe-roots.json")
    }

    /// The .json files directly inside `directory`, deterministically
    /// ordered. A missing directory yields no files (fixtures need not
    /// create all twelve category directories).
    private static func jsonFiles(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Ordering and decoding

    private static let categoryOrder: [ToolCategory: Int] =
        Dictionary(uniqueKeysWithValues: ToolCategory.allCases.enumerated().map { ($1, $0) })

    private static let groupOrder: [ExclusionGroup: Int] =
        Dictionary(uniqueKeysWithValues: ExclusionGroup.allCases.enumerated().map { ($1, $0) })

    private static func displayOrder(_ lhs: CleanupTarget, _ rhs: CleanupTarget) -> Bool {
        (categoryOrder[lhs.category] ?? .max, lhs.id) < (categoryOrder[rhs.category] ?? .max, rhs.id)
    }

    private static func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CatalogueError.invalid(file: url.lastPathComponent, reason: "unreadable: \(error)")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw CatalogueError.invalid(file: url.lastPathComponent, reason: "undecodable: \(error)")
        }
    }
}
