//
//  Spacing.swift
//  Reclaim
//
//  The sanctioned distances. Tier 1: semantic tokens, named for their
//  role, added as sweeps identify real clusters — never named for
//  their value. Tier 2: the pixel ramp below — value-preserving
//  stand-ins that keep every distance in the design system without
//  inventing fake semantics; promote a ramp use to a semantic token
//  when its role becomes clear. A token's value always equals the
//  literals it replaced: re-theming is a later, deliberate act.
//

import SwiftUI

extension Theme {
    /// Tier-2 pixel ramp — one entry per distance the UI actually uses.
    enum Space {
        static let s0: CGFloat = 0
        static let s1: CGFloat = 1
        static let s2: CGFloat = 2
        static let s3: CGFloat = 3
        static let s4: CGFloat = 4
        static let s5: CGFloat = 5
        static let s6: CGFloat = 6
        static let s7: CGFloat = 7
        static let s8: CGFloat = 8
        static let s9: CGFloat = 9
        static let s10: CGFloat = 10
        static let s11: CGFloat = 11
        static let s12: CGFloat = 12
        static let s13: CGFloat = 13
        static let s14: CGFloat = 14
        static let s15: CGFloat = 15
        static let s16: CGFloat = 16
        static let s18: CGFloat = 18
        static let s20: CGFloat = 20
        static let s22: CGFloat = 22
        static let s24: CGFloat = 24
        static let s26: CGFloat = 26
        static let s27: CGFloat = 27
        static let s28: CGFloat = 28
        static let s30: CGFloat = 30
        static let s32: CGFloat = 32
        static let s36: CGFloat = 36
        static let s40: CGFloat = 40
        static let s44: CGFloat = 44
        static let s46: CGFloat = 46
        static let s48: CGFloat = 48
        static let s52: CGFloat = 52
        static let s60: CGFloat = 60
        static let s64: CGFloat = 64
    }
}

extension Theme {
    /// Tier-1 — gap between elements in a ranked list row
    /// (BiggestRow, ProjectFindingRow).
    static let rowGap: CGFloat = 12
    /// Tier-1 — horizontal padding inside a category chip.
    static let chipPaddingHorizontal: CGFloat = 8
    /// Tier-1 — vertical padding inside a category chip.
    static let chipPaddingVertical: CGFloat = 6
}

extension Theme {
    /// Tier-1 — corner radius for compact 22×22pt icon-chip backgrounds
    /// and close buttons (below `radiusChip`).
    static let radiusIconChip: CGFloat = 6
    /// Tier-1 — corner radius for small status badge chips (history
    /// disposal badge).
    static let radiusBadge: CGFloat = 5
}
