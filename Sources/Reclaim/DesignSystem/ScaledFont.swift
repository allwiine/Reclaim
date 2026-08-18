//
//  ScaledFont.swift
//  Reclaim
//
//  Dynamic Type support without changing the visual design at the
//  default text size. `@ScaledMetric(relativeTo: .body)` returns the
//  base size unchanged at the default size category, so every screen
//  renders exactly as before for the vast majority of users, and text
//  grows only when the system text size is increased.
//
//  Fonts are applied through `.themeFont(_:)` (the named text roles) and
//  `.scaledFont(size:weight:)` (ad-hoc sizes) instead of a static
//  `Font`, because a `Font` value cannot read the environment.
//

import SwiftUI

extension Theme {
    /// The app's named text roles, mirroring the static `Theme` font
    /// tokens so their sizes stay single-sourced here.
    enum TextRole {
        case label, rowTitle, cardTitle, body, footnote, caption

        var size: CGFloat {
            switch self {
            case .label: 11
            case .rowTitle: 13
            case .cardTitle: 13.5
            case .body: 12.5
            case .footnote: 11.5
            case .caption: 11
            }
        }

        var weight: Font.Weight {
            switch self {
            case .label: .semibold
            case .rowTitle, .cardTitle: .medium
            case .body, .footnote, .caption: .regular
            }
        }
    }
}

private struct ThemeFontModifier: ViewModifier {
    let role: Theme.TextRole
    @ScaledMetric private var size: CGFloat

    init(role: Theme.TextRole) {
        self.role = role
        _size = ScaledMetric(wrappedValue: role.size, relativeTo: .body)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: role.weight))
    }
}

private struct ScaledFontModifier: ViewModifier {
    let weight: Font.Weight
    let design: Font.Design
    @ScaledMetric private var size: CGFloat

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        self.weight = weight
        self.design = design
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// Apply a named Theme text role that scales with the system text
    /// size. Identical to the fixed `Theme` font at the default size.
    func themeFont(_ role: Theme.TextRole) -> some View {
        modifier(ThemeFontModifier(role: role))
    }

    /// Apply an ad-hoc system font that scales with the system text size.
    /// Identical to `.font(.system(size:weight:design:))` at the default.
    func scaledFont(
        size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default
    ) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, design: design))
    }
}
