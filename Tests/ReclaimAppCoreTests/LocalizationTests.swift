//
//  LocalizationTests.swift
//  ReclaimAppCoreTests
//
//  The AppCore catalogues must stay complete and in parity between
//  English and Norwegian.
//

import Foundation
import ReclaimKit
import Testing
@testable import ReclaimAppCore

@Suite("ReclaimAppCore localization catalogues")
struct AppCoreLocalizationTests {
    static let locales = ["en", "nb"]

    /// Every key AppModel looks up in this module's catalogues.
    static let stringKeys = [
        "clean.failureLine",
        "projects.artifactLabel",
    ]

    private func lproj(_ locale: String) throws -> URL {
        let url = LocalizationResources.bundle.url(forResource: locale, withExtension: "lproj")
        return try #require(url, "missing \(locale).lproj in ReclaimAppCore resources")
    }

    private func strings(_ locale: String) throws -> [String: String] {
        let url = try lproj(locale).appending(path: "Localizable.strings")
        return try #require(NSDictionary(contentsOf: url) as? [String: String])
    }

    @Test("en and nb define identical, complete key sets")
    func catalogueParity() throws {
        let en = try strings("en")
        let nb = try strings("nb")
        #expect(Set(en.keys) == Set(nb.keys))
        #expect(Set(en.keys) == Set(Self.stringKeys))
        for table in [en, nb] {
            for (key, value) in table {
                #expect(!value.isEmpty, "\(key) is empty")
            }
        }
    }

    @Test("The failure line resolves with both arguments in place")
    func failureLineResolves() {
        let line = localized(
            "clean.failureLine",
            defaultValue: "\("Gradle caches") — \("locked")"
        )
        #expect(line.contains("Gradle caches"))
        #expect(line.contains("locked"))
        #expect(!line.contains("%"), "unresolved format: \(line)")
    }
}
