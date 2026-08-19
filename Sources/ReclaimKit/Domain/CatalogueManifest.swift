//
//  CatalogueManifest.swift
//  ReclaimKit
//
//  File-shaped (Decodable) representations of the JSON catalogue under
//  Sources/ReclaimKit/Catalogue/. These are decode-only DTOs: the
//  CatalogueLoader maps them onto the domain types (CleanupTarget,
//  StructuralExclusion), resolving localized text to plain Strings so
//  the rest of the app never sees per-locale data.
//
//  The manifest format is documented field-by-field in
//  Catalogue/schema/*.schema.json and docs/CATALOGUE.md.
//

import Foundation

/// The locales every catalogue text object must carry.
///
/// Extending this list makes the locale-completeness test in
/// CatalogueConventionTests enumerate every manifest that needs
/// backfilling — that failing test IS the migration checklist.
public enum CatalogueLocales {
    public static let supported: [String] = ["en", "nb"]
    public static let fallback = "en"
}

/// A per-locale text object: `{ "en": "…", "nb": "…" }`.
struct LocalizedText: Decodable, Equatable {
    let values: [String: String]

    init(values: [String: String]) {
        self.values = values
    }

    init(from decoder: any Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: String].self)
    }

    /// The text for the first matching language, falling back to
    /// English (completeness of which is test-enforced).
    func resolved(preferring languages: [String]) -> String {
        for language in languages {
            if let value = values[language] { return value }
        }
        return values[CatalogueLocales.fallback] ?? values.first?.value ?? ""
    }
}

/// A manifest that failed validation. The file name makes test output
/// and Console logs point straight at the offending file.
enum CatalogueError: Error, CustomStringConvertible {
    case invalid(file: String, reason: String)

    var description: String {
        switch self {
        case let .invalid(file, reason): "\(file): \(reason)"
        }
    }
}

/// One target manifest file (`Catalogue/<category>/<id>.json`).
struct TargetManifest: Decodable {
    let id: String
    let category: String
    let safety: String
    let paths: [String]?
    let strategy: String
    let command: CommandManifest?
    let instructions: LocalizedText?
    let relatedApps: [String]?
    let name: LocalizedText
    let summary: LocalizedText
    let note: LocalizedText?
}

/// The `command` companion object for `"strategy": "command"`.
struct CommandManifest: Decodable {
    let executable: String
    let arguments: [String]
    let display: String
    let availabilityProbe: String?
}

/// One exclusion manifest file (`Catalogue/exclusions/<id>.json`).
struct ExclusionManifest: Decodable {
    let id: String
    let group: String
    let paths: [String]
    let reason: LocalizedText
}

extension TargetManifest {
    /// Maps the manifest onto the domain type, resolving localized
    /// text for `languages`. `file` names the manifest in errors.
    func cleanupTarget(preferring languages: [String], file: String) throws -> CleanupTarget {
        guard let toolCategory = ToolCategory(rawValue: category) else {
            throw CatalogueError.invalid(file: file, reason: "unknown category '\(category)'")
        }
        let safetyLevel: SafetyLevel = switch safety {
        case "safe": .safe
        case "caution": .caution
        case "destructive": .destructive
        default:
            throw CatalogueError.invalid(file: file, reason: "unknown safety '\(safety)'")
        }
        let cleanupStrategy: CleanupStrategy
        switch strategy {
        case "removeContents", "removePaths":
            guard command == nil, instructions == nil else {
                throw CatalogueError.invalid(
                    file: file,
                    reason: "'\(strategy)' takes no command or instructions"
                )
            }
            cleanupStrategy = strategy == "removeContents" ? .removeContents : .removePaths
        case "command":
            guard let command, instructions == nil else {
                throw CatalogueError.invalid(
                    file: file,
                    reason: "'command' requires a command object and no instructions"
                )
            }
            cleanupStrategy = .command(CommandSpec(
                executablePath: command.executable,
                arguments: command.arguments,
                displayCommand: command.display,
                availabilityProbePattern: command.availabilityProbe
            ))
        case "manual":
            guard let instructions, command == nil else {
                throw CatalogueError.invalid(
                    file: file,
                    reason: "'manual' requires instructions and no command object"
                )
            }
            cleanupStrategy = .manual(instructions: instructions.resolved(preferring: languages))
        default:
            throw CatalogueError.invalid(file: file, reason: "unknown strategy '\(strategy)'")
        }
        return CleanupTarget(
            id: id,
            name: name.resolved(preferring: languages),
            summary: summary.resolved(preferring: languages),
            category: toolCategory,
            safety: safetyLevel,
            pathPatterns: paths ?? [],
            strategy: cleanupStrategy,
            note: note.map { $0.resolved(preferring: languages) },
            relatedAppBundleIDs: relatedApps ?? []
        )
    }
}

extension ExclusionManifest {
    /// Maps the manifest onto the domain type. `file` names the
    /// manifest in errors.
    func structuralExclusion(preferring languages: [String], file: String) throws -> StructuralExclusion {
        guard let exclusionGroup = ExclusionGroup(rawValue: group) else {
            throw CatalogueError.invalid(file: file, reason: "unknown group '\(group)'")
        }
        return StructuralExclusion(
            id: id,
            paths: paths,
            group: exclusionGroup,
            reason: reason.resolved(preferring: languages)
        )
    }
}
