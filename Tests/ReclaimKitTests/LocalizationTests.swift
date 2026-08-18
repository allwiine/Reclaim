//
//  LocalizationTests.swift
//  ReclaimKitTests
//
//  Guarantees behind "everything user-facing is localized": the en and
//  nb catalogues carry identical key sets, and every string the domain
//  model exposes (registry text, category titles, safety labels)
//  resolves in both locales. Break a catalogue, break the build.
//

import Foundation
import Testing
@testable import ReclaimKit

@Suite("ReclaimKit localization catalogues")
struct KitLocalizationTests {
    static let locales = ["en", "nb"]

    private func lproj(_ locale: String) throws -> URL {
        let url = LocalizationResources.bundle.url(forResource: locale, withExtension: "lproj")
        return try #require(url, "missing \(locale).lproj in ReclaimKit resources")
    }

    /// Keys and values of a locale's Localizable table.
    private func strings(_ locale: String, table: String) throws -> [String: String] {
        let url = try lproj(locale).appending(path: table)
        let dictionary = try #require(
            NSDictionary(contentsOf: url) as? [String: String],
            "unreadable \(locale)/\(table)"
        )
        return dictionary
    }

    /// Top-level keys of a locale's stringsdict.
    private func pluralKeys(_ locale: String) throws -> Set<String> {
        let url = try lproj(locale).appending(path: "Localizable.stringsdict")
        let dictionary = try #require(
            NSDictionary(contentsOf: url) as? [String: Any],
            "unreadable \(locale)/Localizable.stringsdict"
        )
        return Set(dictionary.keys)
    }

    /// Whether `key` is defined for the locale (strings or stringsdict).
    private func defines(_ key: String, in locale: String) throws -> Bool {
        if try strings(locale, table: "Localizable.strings")[key] != nil { return true }
        return try pluralKeys(locale).contains(key)
    }

    @Test("en and nb define identical key sets with non-empty values")
    func catalogueParity() throws {
        let en = try strings("en", table: "Localizable.strings")
        let nb = try strings("nb", table: "Localizable.strings")
        #expect(Set(en.keys) == Set(nb.keys))
        for (key, value) in en {
            #expect(!value.isEmpty, "en value for \(key) is empty")
        }
        for (key, value) in nb {
            #expect(!value.isEmpty, "nb value for \(key) is empty")
        }
        #expect(try pluralKeys("en") == pluralKeys("nb"))
    }

    @Test("Every registry target has catalogue entries in every locale")
    func registryCoverage() throws {
        for locale in Self.locales {
            for target in TargetRegistry.all {
                #expect(
                    try defines("target.\(target.id).name", in: locale),
                    "\(locale): missing name for \(target.id)"
                )
                #expect(
                    try defines("target.\(target.id).summary", in: locale),
                    "\(locale): missing summary for \(target.id)"
                )
                if target.note != nil {
                    #expect(
                        try defines("target.\(target.id).note", in: locale),
                        "\(locale): missing note for \(target.id)"
                    )
                }
                if case .manual = target.strategy {
                    #expect(
                        try defines("target.\(target.id).instructions", in: locale),
                        "\(locale): missing instructions for \(target.id)"
                    )
                }
            }
        }
    }

    @Test("Category and safety labels exist in every locale")
    func enumCoverage() throws {
        for locale in Self.locales {
            for category in ToolCategory.allCases {
                #expect(
                    try defines("category.\(category.rawValue).title", in: locale),
                    "\(locale): missing title for \(category.rawValue)"
                )
            }
            // Derive the key slugs from the enum itself so a new
            // SafetyLevel case can't be added without extending this
            // exhaustive switch (and thus its localization coverage).
            for level in SafetyLevel.allCases {
                let slug: String = switch level {
                case .safe: "safe"
                case .caution: "caution"
                case .destructive: "destructive"
                }
                #expect(try defines("safety.\(slug).title", in: locale))
                #expect(try defines("safety.\(slug).explanation", in: locale))
            }
            let serviceKeys = [
                "engine.commandExitStatus",
                "engine.toolReported",
                "sizer.unreadableRoot",
                "breakdown.moreItems",
            ]
            for key in serviceKeys {
                #expect(try defines(key, in: locale), "\(locale): missing \(key)")
            }
        }
    }

    @Test("Norwegian is a real translation, not a copy of English")
    func norwegianDiffers() throws {
        let en = try strings("en", table: "Localizable.strings")
        let nb = try strings("nb", table: "Localizable.strings")
        // Spot checks on strings that must differ; many keys (brand
        // names like "Android Studio") are legitimately identical.
        for key in ["safety.safe.title", "safety.caution.explanation", "target.xcode-derived-data.summary"] {
            #expect(en[key] != nb[key], "\(key) looks untranslated")
        }
    }

    @Test("Manual instructions keep their backticked command in every locale")
    func manualCommandSurvivesTranslation() throws {
        for locale in Self.locales {
            let table = try strings(locale, table: "Localizable.strings")
            for target in TargetRegistry.all {
                guard case .manual = target.strategy else { continue }
                let instructions = try #require(table["target.\(target.id).instructions"])
                #expect(
                    instructions.contains("`"),
                    "\(locale): instructions for \(target.id) lost the command"
                )
            }
        }
    }
}
