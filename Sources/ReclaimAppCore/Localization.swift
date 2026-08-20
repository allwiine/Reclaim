//
//  Localization.swift
//  ReclaimAppCore
//
//  The one lookup path for user-facing text in this module. Strings
//  live in Resources/{en,nb}.lproj; the inline defaultValue keeps call
//  sites readable and is the fallback when a key is missing.
//

import Foundation

/// Resolves a semantic key against this module's string catalogues.
/// A pure bundle read, so it stays callable from pass code and value
/// contexts rather than inheriting the module's MainActor default.
nonisolated func localized(_ key: StaticString, defaultValue: String.LocalizationValue) -> String {
    String(localized: key, defaultValue: defaultValue, bundle: .module)
}

/// Test hook: the resource bundle holding this module's catalogues.
enum LocalizationResources {
    static let bundle = Bundle.module
}
