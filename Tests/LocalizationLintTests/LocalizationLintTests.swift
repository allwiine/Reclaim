//
//  LocalizationLintTests.swift
//  LocalizationLintTests
//
//  Repo-level guarantees behind "no hardcoded user-facing strings":
//
//  1. Every `localized("key", …)` reference in a module exists in that
//     module's en and nb catalogues.
//  2. Each module's en and nb catalogues define identical key sets.
//  3. The view layer never uses SwiftUI's literal-key inits
//     (`Text("…")`, `Button("…")`, `.help("…")`, …) — those resolve
//     against the main bundle, which has no tables in an SPM build,
//     so a literal there is a string that silently escapes both
//     catalogues.
//
//  The lint parses the source tree directly (anchored via #filePath),
//  so it needs no bundle access and runs everywhere `swift test` runs.
//  Preview-only code (below "// MARK: - Previews", or PreviewData) is
//  exempt: it is DEBUG-only fixture content.
//

import Foundation
import Testing

@Suite("Localization source lint")
struct LocalizationLintTests {
    // MARK: - Repo layout

    static let repoRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let modules = ["ReclaimKit", "ReclaimAppCore", "Reclaim"]
    static let locales = ["en", "nb"]

    // MARK: - Helpers

    private func swiftFiles(inModule module: String) throws -> [URL] {
        let root = Self.repoRoot.appending(path: "Sources/\(module)")
        let enumerator = try #require(FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil
        ))
        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            return url
        }
    }

    /// Source with comment lines and preview sections removed.
    private func lintableSource(of url: URL) throws -> String {
        var contents = try String(contentsOf: url, encoding: .utf8)
        if url.lastPathComponent == "PreviewData.swift" { return "" }
        if let range = contents.range(of: "// MARK: - Previews") {
            contents = String(contents[..<range.lowerBound])
        }
        return contents
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func stringsKeys(module: String, locale: String) throws -> Set<String> {
        let url = Self.repoRoot.appending(
            path: "Sources/\(module)/Resources/\(locale).lproj/Localizable.strings"
        )
        let contents = try NSString(contentsOf: url, encoding: NSUTF8StringEncoding)
        let table = try #require(
            contents.propertyListFromStringsFileFormat() as? [String: String],
            "unparsable \(module)/\(locale) strings table"
        )
        for (key, value) in table {
            #expect(!value.isEmpty, "\(module)/\(locale): empty value for \(key)")
        }
        return Set(table.keys)
    }

    private func pluralKeys(module: String, locale: String) throws -> Set<String> {
        let url = Self.repoRoot.appending(
            path: "Sources/\(module)/Resources/\(locale).lproj/Localizable.stringsdict"
        )
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        return Set(plist.keys)
    }

    private func catalogueKeys(module: String, locale: String) throws -> Set<String> {
        try stringsKeys(module: module, locale: locale)
            .union(pluralKeys(module: module, locale: locale))
    }

    // MARK: - Tests

    @Test("Every localized(…) reference has entries in both catalogues", arguments: modules)
    func referencesResolve(module: String) throws {
        let pattern = /localized\(\s*"([^"]+)"/
        var referenced: Set<String> = []
        for file in try swiftFiles(inModule: module) {
            let source = try lintableSource(of: file)
            for match in source.matches(of: pattern) {
                referenced.insert(String(match.1))
            }
        }
        for locale in Self.locales {
            let defined = try catalogueKeys(module: module, locale: locale)
            let missing = referenced.subtracting(defined)
            #expect(missing.isEmpty, "\(module)/\(locale) is missing keys: \(missing.sorted())")
        }
    }

    @Test("en and nb catalogues define identical key sets", arguments: modules)
    func catalogueParity(module: String) throws {
        let en = try catalogueKeys(module: module, locale: "en")
        let nb = try catalogueKeys(module: module, locale: "nb")
        #expect(
            en == nb,
            "\(module): en-only \(en.subtracting(nb).sorted()), nb-only \(nb.subtracting(en).sorted())"
        )
    }

    @Test("The view layer never uses literal-key SwiftUI inits")
    func noLiteralUIStrings() throws {
        let componentInit = /(?:^|[^A-Za-z0-9_])(?:Text|Button|Toggle|TextField|Label|SectionLabel|MenuBarExtra)\(\s*"/
        let modifierInit = /\.(?:help|accessibilityLabel|navigationTitle|confirmationDialog)\(\s*"[^"]/
        for file in try swiftFiles(inModule: "Reclaim") {
            let source = try lintableSource(of: file)
            for (line, text) in source.components(separatedBy: .newlines).enumerated() {
                #expect(
                    text.firstMatch(of: componentInit) == nil,
                    "\(file.lastPathComponent):\(line + 1) passes a literal to a SwiftUI component: \(text.trimmingCharacters(in: .whitespaces))"
                )
                #expect(
                    text.firstMatch(of: modifierInit) == nil,
                    "\(file.lastPathComponent):\(line + 1) passes a literal to a SwiftUI modifier: \(text.trimmingCharacters(in: .whitespaces))"
                )
            }
        }
    }
}
