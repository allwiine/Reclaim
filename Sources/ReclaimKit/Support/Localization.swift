//
//  Localization.swift
//  ReclaimKit
//
//  The one lookup path for user-facing text in this module. Strings
//  live in Resources/{en,nb}.lproj (Localizable.strings for singular
//  text, Localizable.stringsdict for plural rules); the inline
//  defaultValue keeps call sites readable and is the fallback when a
//  key is missing from the catalogues.
//
//  Built with `swift build`, so classic .lproj tables are used —
//  .xcstrings catalogs are only compiled by Xcode's build system.
//

import Foundation

/// Resolves a semantic key against this module's string catalogues.
func localized(_ key: StaticString, defaultValue: String.LocalizationValue) -> String {
    String(localized: key, defaultValue: defaultValue, bundle: .module)
}

/// Test hook: the resource bundle holding this module's catalogues,
/// so LocalizationTests can open the per-locale tables directly
/// (`String(localized:locale:)` does not switch bundle language).
enum LocalizationResources {
    static let bundle = Bundle.module
}
