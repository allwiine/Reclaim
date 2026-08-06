//
//  LocalizationTests.swift
//  ReclaimAppCoreTests
//
//  The AppCore catalogues (clean-summary copy) must stay complete and
//  in parity between English and Norwegian, and the plural-bearing
//  summary message must render through the stringsdict rules.
//

import Foundation
import ReclaimKit
import Testing
@testable import ReclaimAppCore

@Suite("ReclaimAppCore localization catalogues")
struct AppCoreLocalizationTests {
    static let locales = ["en", "nb"]

    /// Every key CleanSummary/AppModel look up, split by table.
    static let stringKeys = [
        "summary.dryRun",
        "summary.stoppedEarly",
        "summary.nothingCleaned",
        "summary.failuresHeading",
        "summary.failuresMore",
        "summary.fullDiskAccessHint",
        "clean.failureLine",
    ]
    static let pluralKeys = [
        "summary.movedToTrash",
        "summary.deletedPermanently",
    ]

    private func lproj(_ locale: String) throws -> URL {
        let url = LocalizationResources.bundle.url(forResource: locale, withExtension: "lproj")
        return try #require(url, "missing \(locale).lproj in ReclaimAppCore resources")
    }

    private func strings(_ locale: String) throws -> [String: String] {
        let url = try lproj(locale).appending(path: "Localizable.strings")
        return try #require(NSDictionary(contentsOf: url) as? [String: String])
    }

    private func plurals(_ locale: String) throws -> Set<String> {
        let url = try lproj(locale).appending(path: "Localizable.stringsdict")
        let dictionary = try #require(NSDictionary(contentsOf: url) as? [String: Any])
        return Set(dictionary.keys)
    }

    @Test("en and nb define identical, complete key sets")
    func catalogueParity() throws {
        let en = try strings("en")
        let nb = try strings("nb")
        #expect(Set(en.keys) == Set(nb.keys))
        #expect(Set(en.keys) == Set(Self.stringKeys))
        #expect(try plurals("en") == plurals("nb"))
        #expect(try plurals("en") == Set(Self.pluralKeys))
        for table in [en, nb] {
            for (key, value) in table {
                #expect(!value.isEmpty, "\(key) is empty")
            }
        }
    }

    @Test("The summary message pluralizes through the catalogue")
    func summaryMessagePluralizes() {
        var summary = CleanSummary(disposal: .trash)
        summary.itemsRemoved = 1
        summary.cleanedTargets = 1
        summary.reclaimedBytes = 1_000_000_000

        // The process runs under the default (English) localization in
        // tests; singular forms must come out of the stringsdict rules.
        let singular = summary.message
        #expect(!singular.contains("1 items"), "plural rule not applied: \(singular)")
        #expect(!singular.contains("summary."), "raw key leaked: \(singular)")

        summary.itemsRemoved = 3
        summary.cleanedTargets = 2
        let plural = summary.message
        #expect(!plural.contains("3 item ") && !plural.contains("2 location "), "singular leaked: \(plural)")
        #expect(!plural.contains("%"), "unresolved format: \(plural)")
    }
}
