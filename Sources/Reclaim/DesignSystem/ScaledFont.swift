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
        /// Numeric byte-amount figures in list rows.
        case amount
        /// Small muted label/value text in compact rows (disk legend,
        /// project rows).
        case meta
        /// Full Disk Access warning glyph.
        case warningIcon
        /// Disclosure chevron glyph.
        case disclosure
        /// Emphasized inline stat, e.g. project count and size.
        case figure
        /// Small inline icon glyph (project-row folder icon).
        case miniIcon
        /// Emphasized 12pt text/icon (category tile title, catalogue
        /// projects-row icon).
        case tileLabel
        /// Prominent value on a category tile (byte total).
        case tileValue
        /// Unit label beside the reclaimable ring's hero number.
        case ringUnit
        /// Small bold eyebrow label above a headline (version badge).
        case eyebrow
        /// Idle screen's hero headline.
        case headline
        /// Idle screen's lead paragraph.
        case lead
        /// Trust-statement checkmark glyph.
        case trustIcon
        /// Category chip / "more" chip label text.
        case chipLabel
        /// Failures/warning card title.
        case warningTitle
        /// Cleaned-item name in the Done screen's lists.
        case itemName
        /// Done screen's result glyph (checkmark/eye/triangle).
        case resultIcon
        /// Done screen's "nothing cleaned" fallback headline.
        case resultHeadline
        /// Unit/caption beside the Done screen's hero byte number.
        case heroUnit

        var size: CGFloat {
            switch self {
            case .label: 11
            case .rowTitle: 13
            case .cardTitle: 13.5
            case .body: 12.5
            case .footnote: 11.5
            case .caption: 11
            case .amount: 12.5
            case .meta: 12
            case .warningIcon: 16
            case .disclosure: 10
            case .figure: 14
            case .miniIcon: 10.5
            case .tileLabel: 12
            case .tileValue: 17
            case .ringUnit: 10.5
            case .eyebrow: 11
            case .headline: 40
            case .lead: 14.5
            case .trustIcon: 17
            case .chipLabel: 11.5
            case .warningTitle: 12
            case .itemName: 13
            case .resultIcon: 24
            case .resultHeadline: 28
            case .heroUnit: 19
            }
        }

        var weight: Font.Weight {
            switch self {
            case .label: .semibold
            case .rowTitle, .cardTitle: .medium
            case .body, .footnote, .caption: .regular
            case .amount, .tileLabel, .chipLabel: .medium
            case .meta, .warningIcon, .miniIcon, .lead, .trustIcon, .itemName: .regular
            case .disclosure, .figure, .ringUnit, .resultIcon, .warningTitle: .semibold
            case .tileValue, .eyebrow, .headline, .resultHeadline: .bold
            case .heroUnit: .medium
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
