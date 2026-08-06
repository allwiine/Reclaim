//
//  Localization.swift
//  Reclaim
//
//  The one lookup path for user-facing text in the app target. Strings
//  live in Resources/{en,nb}.lproj; the inline defaultValue keeps call
//  sites readable and is the fallback when a key is missing.
//
//  Views pass the resolved String to SwiftUI (`Text(localized(…))`),
//  never a bare literal: literal-key inits (`Text("…")`, `Button("…")`,
//  `.help("…")`) would resolve against the main bundle, which has no
//  tables when running from an SPM build.
//

import Foundation

/// Resolves a semantic key against this module's string catalogues.
func localized(_ key: StaticString, defaultValue: String.LocalizationValue) -> String {
    String(localized: key, defaultValue: defaultValue, bundle: .module)
}

/// Test hook: the resource bundle holding this module's catalogues.
enum LocalizationResources {
    static let bundle = Bundle.module
}
