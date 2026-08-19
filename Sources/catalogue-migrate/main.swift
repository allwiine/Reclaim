//
//  main.swift — catalogue-migrate
//
//  ONE-SHOT tool: converts the Swift TargetRegistry / ExclusionRegistry
//  literals plus the en/nb Localizable.strings tables into the JSON
//  catalogue under Sources/ReclaimKit/Catalogue/. Idempotent — safe to
//  re-run; it overwrites its own output. Deleted once the migration
//  lands (see the implementation plan).
//
//  Run from the repository root:
//      swift run catalogue-migrate -AppleLanguages '(en)'
//
//  The -AppleLanguages argument forces Foundation to resolve the
//  registry's localized strings in English, which the reason
//  reverse-lookup below depends on. The tool verifies this and dies
//  with instructions if the process resolves another language.
//

import Foundation
import ReclaimKit

// MARK: - Ordered JSON writer
// JSONEncoder can only sort keys alphabetically; these files are the
// project's primary contribution surface and should read in canonical
// order, with Norwegian characters kept literal (no \u escapes).

indirect enum JSONValue {
    case string(String)
    case array([JSONValue])
    case object([(String, JSONValue)])

    func rendered(indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        let inner = String(repeating: "  ", count: indent + 1)
        switch self {
        case .string(let value):
            return "\"\(Self.escape(value))\""
        case .array(let items):
            if items.isEmpty { return "[]" }
            let body = items
                .map { inner + $0.rendered(indent: indent + 1) }
                .joined(separator: ",\n")
            return "[\n\(body)\n\(pad)]"
        case .object(let pairs):
            let body = pairs
                .map { inner + "\"\(Self.escape($0.0))\": " + $0.1.rendered(indent: indent + 1) }
                .joined(separator: ",\n")
            return "{\n\(body)\n\(pad)}"
        }
    }

    static func escape(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }
}

// MARK: - Inputs

let fm = FileManager.default
guard fm.fileExists(atPath: "Package.swift") else {
    fatalError("Run from the repository root (Package.swift not found).")
}

func stringsTable(_ locale: String) -> [String: String] {
    let path = "Sources/ReclaimKit/Resources/\(locale).lproj/Localizable.strings"
    guard let table = NSDictionary(contentsOfFile: path) as? [String: String] else {
        fatalError("Unreadable strings table at \(path)")
    }
    return table
}

let en = stringsTable("en")
let nb = stringsTable("nb")

// Verify the process resolves English (see the header comment).
if let probe = ExclusionRegistry.all.first(where: { $0.id == "claude-auth" }),
   probe.reason != en["exclusion.reason.authAppState"] {
    fatalError("""
    The process is not resolving English strings. Re-run as:
        swift run catalogue-migrate -AppleLanguages '(en)'
    """)
}

/// Localized text pulled from both tables for a `target.*` key.
func localizedText(_ key: String) -> JSONValue {
    guard let english = en[key], let norwegian = nb[key] else {
        fatalError("Missing \(key) in the en or nb catalogue")
    }
    return .object([("en", .string(english)), ("nb", .string(norwegian))])
}

// MARK: - Output

let catalogueRoot = URL(fileURLWithPath: "Sources/ReclaimKit/Catalogue")

@MainActor
func write(_ value: JSONValue, to url: URL) {
    do {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((value.rendered() + "\n").utf8).write(to: url)
    } catch {
        fatalError("Cannot write \(url.path): \(error)")
    }
}

// MARK: - Targets

for target in TargetRegistry.all {
    var pairs: [(String, JSONValue)] = [
        ("$schema", .string("../schema/target.schema.json")),
        ("id", .string(target.id)),
        ("category", .string(target.category.rawValue)),
    ]
    let safety: String = switch target.safety {
    case .safe: "safe"
    case .caution: "caution"
    case .destructive: "destructive"
    }
    pairs.append(("safety", .string(safety)))
    if !target.pathPatterns.isEmpty {
        pairs.append(("paths", .array(target.pathPatterns.map(JSONValue.string))))
    }
    switch target.strategy {
    case .removeContents:
        pairs.append(("strategy", .string("removeContents")))
    case .removePaths:
        pairs.append(("strategy", .string("removePaths")))
    case .command(let spec):
        pairs.append(("strategy", .string("command")))
        var command: [(String, JSONValue)] = [
            ("executable", .string(spec.executablePath)),
            ("arguments", .array(spec.arguments.map(JSONValue.string))),
            ("display", .string(spec.displayCommand)),
        ]
        if let probe = spec.availabilityProbePattern {
            command.append(("availabilityProbe", .string(probe)))
        }
        pairs.append(("command", .object(command)))
    case .manual:
        pairs.append(("strategy", .string("manual")))
        pairs.append(("instructions", localizedText("target.\(target.id).instructions")))
    }
    if !target.relatedAppBundleIDs.isEmpty {
        pairs.append(("relatedApps", .array(target.relatedAppBundleIDs.map(JSONValue.string))))
    }
    pairs.append(("name", localizedText("target.\(target.id).name")))
    pairs.append(("summary", localizedText("target.\(target.id).summary")))
    if target.note != nil {
        pairs.append(("note", localizedText("target.\(target.id).note")))
    }
    let url = catalogueRoot
        .appending(path: target.category.rawValue)
        .appending(path: "\(target.id).json")
    write(.object(pairs), to: url)
}

// MARK: - Exclusions
// StructuralExclusion carries the RESOLVED reason string, not its key.
// Reverse-lookup: find the exclusion.reason.* key(s) whose English
// value matches, then take their (necessarily unambiguous) Norwegian.

let reasonKeys = en.filter { $0.key.hasPrefix("exclusion.reason.") }

for exclusion in ExclusionRegistry.all {
    let matches = reasonKeys.filter { $0.value == exclusion.reason }.map(\.key)
    guard !matches.isEmpty else {
        fatalError("\(exclusion.id): no exclusion.reason.* key resolves to '\(exclusion.reason)'")
    }
    let norwegianVariants = Set(matches.compactMap { nb[$0] })
    guard norwegianVariants.count == 1, let norwegian = norwegianVariants.first else {
        fatalError("\(exclusion.id): ambiguous Norwegian for reason '\(exclusion.reason)': \(norwegianVariants)")
    }
    let pairs: [(String, JSONValue)] = [
        ("$schema", .string("../schema/exclusion.schema.json")),
        ("id", .string(exclusion.id)),
        ("group", .string(exclusion.group.rawValue)),
        ("paths", .array(exclusion.paths.map(JSONValue.string))),
        ("reason", .object([("en", .string(exclusion.reason)), ("nb", .string(norwegian))])),
    ]
    write(.object(pairs), to: catalogueRoot.appending(path: "exclusions/\(exclusion.id).json"))
}

// MARK: - Reviewed-safe roots
// The rationale for each root lives only in Swift comments; parse them
// out of the source so no review knowledge is lost.

guard let registrySource = try? String(
    contentsOfFile: "Sources/ReclaimKit/Domain/ExclusionRegistry.swift", encoding: .utf8
) else {
    fatalError("Cannot read ExclusionRegistry.swift")
}
var rationales: [String: String] = [:]
var inRootsBlock = false
for line in registrySource.split(separator: "\n", omittingEmptySubsequences: false) {
    if line.contains("reviewedSafeRoots: Set<String> = [") {
        inRootsBlock = true
        continue
    }
    guard inRootsBlock else { continue }
    if line.trimmingCharacters(in: .whitespaces) == "]" { break }
    // Shape: `        "~/.aider",         // caches and tags only; …`
    guard let match = line.firstMatch(of: /"([^"]+)",\s*\/\/\s*(.+)$/) else { continue }
    rationales[String(match.1)] = String(match.2).trimmingCharacters(in: .whitespaces)
}
for root in ExclusionRegistry.reviewedSafeRoots where rationales[root] == nil {
    fatalError("No rationale comment found for reviewed-safe root \(root)")
}
let rootPairs = rationales
    .filter { ExclusionRegistry.reviewedSafeRoots.contains($0.key) }
    .sorted { $0.key < $1.key }
    .map { ($0.key, JSONValue.string($0.value)) }
write(.object(rootPairs), to: catalogueRoot.appending(path: "exclusions/reviewed-safe-roots.json"))

print("""
Wrote \(TargetRegistry.all.count) targets, \(ExclusionRegistry.all.count) exclusions, \
\(rootPairs.count) reviewed-safe roots.
""")
