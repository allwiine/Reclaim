//
//  CatalogueConventionTests.swift
//  ReclaimKitTests
//
//  Authoring conventions for the JSON catalogue, checked against the
//  SOURCE TREE (not the bundle): these rules govern the files
//  contributors actually write. docs/CATALOGUE.md explains each rule;
//  this suite enforces them.
//

import Foundation
import Testing
@testable import ReclaimKit

@Suite("Catalogue authoring conventions")
struct CatalogueConventionTests {
    /// Repo-relative path of the catalogue, derived from this file's
    /// location: Tests/ReclaimKitTests/ → repo root → Sources/….
    static let catalogueRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/ReclaimKit/Catalogue")

    @Test("Schemas are valid JSON and every property is documented", arguments: ["target", "exclusion"])
    func schemasAreDocumented(name: String) throws {
        let url = Self.catalogueRoot.appending(path: "schema/\(name).schema.json")
        let schema = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let missing = Self.propertiesMissingDescriptions(in: schema, path: name)
        #expect(missing.isEmpty, "properties without a description: \(missing)")
    }

    /// Walks a JSON Schema and returns the paths of `properties`
    /// entries that define a value shape (type/enum/const) without a
    /// "description". Exempt: "$ref" entries (documented at the ref
    /// site), boolean schemas (`"command": false` forbids a key), and
    /// bare refinements (`{"minItems": 1}` inside a conditional).
    private static func propertiesMissingDescriptions(in node: Any, path: String) -> [String] {
        if let array = node as? [Any] {
            return array.flatMap { propertiesMissingDescriptions(in: $0, path: path) }
        }
        guard let object = node as? [String: Any] else { return [] }
        var missing: [String] = []
        if let properties = object["properties"] as? [String: Any] {
            for (key, sub) in properties {
                guard let subObject = sub as? [String: Any] else { continue }
                let definesShape = subObject["type"] != nil
                    || subObject["enum"] != nil
                    || subObject["const"] != nil
                if definesShape, subObject["description"] == nil, subObject["$ref"] == nil {
                    missing.append("\(path).\(key)")
                }
                missing += propertiesMissingDescriptions(in: subObject, path: "\(path).\(key)")
            }
        }
        for (key, value) in object where key != "properties" {
            missing += propertiesMissingDescriptions(in: value, path: "\(path).\(key)")
        }
        return missing.sorted()
    }

    // MARK: - Shared helpers

    private static let allowedTargetKeys: Set<String> = [
        "$schema", "id", "category", "safety", "paths", "strategy",
        "command", "instructions", "relatedApps", "name", "summary", "note",
    ]
    private static let allowedCommandKeys: Set<String> = [
        "executable", "arguments", "display", "availabilityProbe",
    ]
    private static let allowedExclusionKeys: Set<String> = [
        "$schema", "id", "group", "paths", "reason",
    ]
    private static let localizedKeys = Set(CatalogueLocales.supported)

    private static func jsonFiles(in directory: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func targetFiles() throws -> [URL] {
        try ToolCategory.allCases.flatMap {
            try jsonFiles(in: catalogueRoot.appending(path: $0.rawValue))
        }
    }

    private static func exclusionFiles() throws -> [URL] {
        try jsonFiles(in: catalogueRoot.appending(path: "exclusions"))
            .filter { $0.lastPathComponent != "reviewed-safe-roots.json" }
    }

    private static func object(of url: URL) throws -> [String: Any] {
        let any = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return (any as? [String: Any]) ?? [:]
    }

    /// Asserts a localized-text value carries exactly the supported
    /// locales, each non-empty.
    private static func expectCompleteLocalizedText(_ value: Any, field: String, file: String) throws {
        let object = try #require(value as? [String: Any], "\(file): \(field) is not an object")
        #expect(
            Set(object.keys) == localizedKeys,
            "\(file): \(field) must carry exactly \(localizedKeys.sorted())"
        )
        for (locale, text) in object {
            #expect((text as? String)?.isEmpty == false, "\(file): \(field).\(locale) is empty")
        }
    }

    // MARK: - Layout

    @Test("The catalogue holds only category directories, exclusions, schema, and a README")
    func onlyKnownEntries() throws {
        let knownDirectories = Set(ToolCategory.allCases.map(\.rawValue) + ["exclusions", "schema"])
        let entries = try FileManager.default.contentsOfDirectory(
            at: Self.catalogueRoot, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        for url in entries {
            let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            if isDirectory {
                #expect(knownDirectories.contains(url.lastPathComponent),
                        "unexpected directory \(url.lastPathComponent)")
            } else {
                #expect(url.lastPathComponent == "README.md",
                        "unexpected file \(url.lastPathComponent)")
            }
        }
        for category in ToolCategory.allCases {
            let directory = Self.catalogueRoot.appending(path: category.rawValue)
            #expect(FileManager.default.fileExists(atPath: directory.path),
                    "missing directory for category \(category.rawValue)")
        }
    }

    @Test("A manifest's filename is its id, and its directory is its category")
    func filenamesAndDirectoriesAgree() throws {
        for url in try Self.targetFiles() {
            let object = try Self.object(of: url)
            let basename = url.deletingPathExtension().lastPathComponent
            #expect(object["id"] as? String == basename, "\(url.lastPathComponent)")
            #expect(object["category"] as? String == url.deletingLastPathComponent().lastPathComponent,
                    "\(url.lastPathComponent)")
        }
        for url in try Self.exclusionFiles() {
            let object = try Self.object(of: url)
            #expect(object["id"] as? String == url.deletingPathExtension().lastPathComponent,
                    "\(url.lastPathComponent)")
        }
    }

    // MARK: - Manifest shape

    @Test("Target manifests use only documented keys, the right $schema, and complete localized text")
    func targetManifestShape() throws {
        for url in try Self.targetFiles() {
            let file = url.lastPathComponent
            let object = try Self.object(of: url)
            let unknown = Set(object.keys).subtracting(Self.allowedTargetKeys)
            #expect(unknown.isEmpty, "\(file): unknown keys \(unknown.sorted()) — typo?")
            #expect(object["$schema"] as? String == "../schema/target.schema.json", "\(file)")
            if let command = object["command"] as? [String: Any] {
                let unknownCommand = Set(command.keys).subtracting(Self.allowedCommandKeys)
                #expect(unknownCommand.isEmpty, "\(file): unknown command keys \(unknownCommand.sorted())")
            }
            for field in ["name", "summary", "note", "instructions"] {
                guard let value = object[field] else { continue }
                try Self.expectCompleteLocalizedText(value, field: field, file: file)
            }
        }
    }

    @Test("Exclusion manifests use only documented keys, the right $schema, and complete localized text")
    func exclusionManifestShape() throws {
        for url in try Self.exclusionFiles() {
            let file = url.lastPathComponent
            let object = try Self.object(of: url)
            let unknown = Set(object.keys).subtracting(Self.allowedExclusionKeys)
            #expect(unknown.isEmpty, "\(file): unknown keys \(unknown.sorted()) — typo?")
            #expect(object["$schema"] as? String == "../schema/exclusion.schema.json", "\(file)")
            let reason = try #require(object["reason"], "\(file): missing reason")
            try Self.expectCompleteLocalizedText(reason, field: "reason", file: file)
        }
    }

    @Test("reviewed-safe-roots.json maps each root to a review rationale")
    func reviewedSafeRootsShape() throws {
        let url = Self.catalogueRoot.appending(path: "exclusions/reviewed-safe-roots.json")
        let entries = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: String],
            "reviewed-safe-roots.json must map root paths to rationale strings"
        )
        for (root, rationale) in entries {
            #expect(root.hasPrefix("~/") || root.hasPrefix("/"), "\(root)")
            #expect(!root.hasSuffix("/"), "\(root)")
            #expect(!rationale.isEmpty, "\(root) needs a review rationale")
        }
    }

    // MARK: - Loading and text quality

    @Test("Every bundled manifest decodes strictly")
    func bundledCatalogueDecodes() throws {
        let root = try #require(CatalogueLoader.bundledCatalogueURL)
        _ = try CatalogueLoader.loadTargets(from: root, preferring: ["en"])
        _ = try CatalogueLoader.loadExclusions(from: root, preferring: ["en"])
        _ = try CatalogueLoader.loadReviewedSafeRoots(from: root)
    }

    @Test("Norwegian is a real translation, not a copy of English")
    func norwegianIsTranslated() throws {
        // Spot check — many strings (brand names) are legitimately
        // identical across locales, so only known-divergent text is checked.
        let url = Self.catalogueRoot.appending(path: "xcode/xcode-derived-data.json")
        let object = try Self.object(of: url)
        let summary = try #require(object["summary"] as? [String: String])
        #expect(summary["en"] != summary["nb"], "xcode-derived-data summary looks untranslated")
    }

    @Test("Manual instructions keep their backticked command in every locale")
    func manualInstructionsKeepCommands() throws {
        for url in try Self.targetFiles() {
            let object = try Self.object(of: url)
            guard object["strategy"] as? String == "manual" else { continue }
            let instructions = try #require(
                object["instructions"] as? [String: String], "\(url.lastPathComponent)")
            for locale in CatalogueLocales.supported {
                #expect(instructions[locale]?.contains("`") == true,
                        "\(url.lastPathComponent): \(locale) instructions lost the command")
            }
        }
    }
}
