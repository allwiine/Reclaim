//
//  Theme.swift
//  Reclaim
//
//  The single source of truth for the app's visual language: colors,
//  typography, spacing, radii and motion. Every view styles itself
//  through these tokens — change them here, change them everywhere.
//
//  The palette is the design's OKLCH values converted to sRGB. The app
//  is deliberately dark-committed: RootView applies the dark scheme.
//

import ReclaimKit
import SwiftUI

/// Namespace for all design tokens.
enum Theme {
    // MARK: - Surfaces

    /// Content pane background.
    static let background = Color(hex: 0x1E1E21)
    /// Window/sidebar base behind the translucent sidebar fill.
    static let backgroundDeep = Color(hex: 0x1A1A1D)
    /// Elevated sheet/popover surface.
    static let surfaceRaised = Color(hex: 0x2A2A2E)

    /// Standard card fill on the content background.
    static let cardFill = Color.white.opacity(0.04)
    /// Slightly quieter fill (sidebar, tables).
    static let cardFillQuiet = Color.white.opacity(0.035)
    /// Hairline stroke used as an inset border on cards.
    static let hairline = Color.white.opacity(0.075)
    /// Divider/border lines between structural areas.
    static let divider = Color.white.opacity(0.09)
    /// Row separators inside cards.
    static let separator = Color.white.opacity(0.055)
    /// Fill for interactive chips and secondary buttons.
    static let controlFill = Color.white.opacity(0.08)
    /// Hover state for rows and chips.
    static let hoverFill = Color.white.opacity(0.07)
    /// Selected/active row fill.
    static let selectionFill = Color.white.opacity(0.10)
    /// Track behind bars and progress.
    static let barTrack = Color.white.opacity(0.08)

    // MARK: - Text

    static let textPrimary = Color(hex: 0xF2F2F5)
    static let textSecondary = Color(hex: 0x98989F)
    // Tertiary/quaternary lifted to clear WCAG AA (≥4.5:1) on the
    // 0x1E1E21 content background at the 11–12.5 pt sizes they're used
    // at; the earlier 0x78787F/0x6F6F76 sat at ~3.9:1/3.4:1. The
    // hierarchy (secondary > tertiary > quaternary) is preserved.
    static let textTertiary = Color(hex: 0x8E8E95)
    static let textQuaternary = Color(hex: 0x88888F)
    /// Uppercase section labels.
    static let textLabel = Color(hex: 0x86868C)
    /// Body copy on dark hero surfaces.
    static let textBody = Color(hex: 0xA4A4AB)

    // MARK: - Accent (emerald)

    static let accent = Color(hex: 0x4BC899)
    static let accentSoft = Color(hex: 0x82D9B4)
    static let accentLabel = Color(hex: 0x66C7A0)
    /// Text color on top of accent-filled controls.
    static let onAccent = Color(hex: 0x06130E)
    /// Radial glow behind the hero.
    static let accentGlow = Color(hex: 0x1E7359)

    /// Primary button / active control gradient.
    static let accentGradient = LinearGradient(
        colors: [Color(hex: 0x4FCB9C), Color(hex: 0x1AAB81)],
        startPoint: .top, endPoint: .bottom
    )
    /// Progress bar sweep.
    static let progressGradient = LinearGradient(
        colors: [Color(hex: 0x2EB88F), Color(hex: 0x5BD19F)],
        startPoint: .leading, endPoint: .trailing
    )
    /// Destructive confirmation gradient.
    static let dangerGradient = LinearGradient(
        colors: [Color(hex: 0xDA534F), Color(hex: 0xC13C36)],
        startPoint: .top, endPoint: .bottom
    )

    // MARK: - Semantic colors

    static let safe = Color(hex: 0x47C496)
    static let caution = Color(hex: 0xD5A13C)
    static let cautionBright = Color(hex: 0xE3AD4B)
    static let cautionTitle = Color(hex: 0xF5CA7A)
    static let destructive = Color(hex: 0xFF7E76)
    static let dangerWarn = Color(hex: 0xE0615C)
    /// "Handled by tool" — measured but never deleted by Reclaim.
    static let delegated = Color(hex: 0x8DACDE)

    // MARK: - Spacing & radii

    /// Content padding inside cards.
    static let cardPadding: CGFloat = 20
    /// Gap between dashboard cards.
    static let cardGap: CGFloat = 16
    /// Outer content margins.
    static let contentMargin: CGFloat = 24

    static let radiusCard: CGFloat = 13
    static let radiusTile: CGFloat = 12
    static let radiusPanel: CGFloat = 10
    static let radiusInset: CGFloat = 9
    static let radiusControl: CGFloat = 8
    static let radiusChip: CGFloat = 7

    /// Toolbar / window header height.
    static let toolbarHeight: CGFloat = 46
    static let sidebarWidth: CGFloat = 258

    // MARK: - Motion

    /// Standard state change (selection, fills, toggles).
    static let quick = Animation.easeOut(duration: 0.16)
    /// Value/layout change (bars, numbers, cards).
    static let smooth = Animation.smooth(duration: 0.35)
    /// Springy emphasis for entrances and rings.
    static let springy = Animation.spring(response: 0.55, dampingFraction: 0.8)
    /// Full-screen flow transitions.
    static let flow = Animation.snappy(duration: 0.3)
}

// MARK: - Typography

extension Theme {
    /// Uppercase section label ("RECLAIMABLE", "CATEGORIES").
    static let labelFont = Font.system(size: 11, weight: .semibold)
    static let labelTracking: CGFloat = 1.0

    static func heroNumber(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .bold)
    }

    static let rowTitle = Font.system(size: 13, weight: .medium)
    static let cardTitle = Font.system(size: 13.5, weight: .medium)
    static let body = Font.system(size: 12.5)
    static let footnote = Font.system(size: 11.5)
    static let caption = Font.system(size: 11)

    static func mono(_ size: CGFloat = 11) -> Font {
        .system(size: size, design: .monospaced)
    }
}

// MARK: - Domain colors

extension ToolCategory {
    /// Design accent for this category (used in icons, bars, the ring).
    var color: Color {
        switch self {
        case .xcode: Color(hex: 0x67AAED)
        case .android: Color(hex: 0x69BA7C)
        case .dotNet: Color(hex: 0xCF88C8)
        case .gameEngines: Color(hex: 0xD97A7A)
        case .aiTools: Color(hex: 0xE4896A)
        case .packageManagers: Color(hex: 0xB093E5)
        case .containers: Color(hex: 0xDDB55F)
        case .jvm: Color(hex: 0xB58A66)
        case .webTools: Color(hex: 0xA9C763)
        case .cloudDevOps: Color(hex: 0x8FB6D9)
        case .embedded: Color(hex: 0x8C9BAB)
        case .otherTools: Color(hex: 0x14BBC2)
        }
    }

    /// Single-letter glyph shown in category icon tiles.
    var letter: String {
        switch self {
        case .xcode: localized("category.xcode.letter", defaultValue: "X")
        case .android: localized("category.android.letter", defaultValue: "A")
        case .dotNet: localized("category.dotNet.letter", defaultValue: "N")
        case .gameEngines: localized("category.gameEngines.letter", defaultValue: "G")
        case .aiTools: localized("category.aiTools.letter", defaultValue: "AI")
        case .packageManagers: localized("category.packageManagers.letter", defaultValue: "P")
        case .containers: localized("category.containers.letter", defaultValue: "C")
        case .jvm: localized("category.jvm.letter", defaultValue: "J")
        case .webTools: localized("category.webTools.letter", defaultValue: "W")
        case .cloudDevOps: localized("category.cloudDevOps.letter", defaultValue: "CD")
        case .embedded: localized("category.embedded.letter", defaultValue: "E")
        case .otherTools: localized("category.otherTools.letter", defaultValue: "D")
        }
    }
}

extension SafetyLevel {
    var color: Color {
        switch self {
        case .safe: Theme.safe
        case .caution: Theme.caution
        case .destructive: Theme.destructive
        }
    }
}

/// How a target's risk is badged: its safety level, except that items
/// Reclaim only measures (Docker, Go modules) read "Handled by tool".
enum BadgeKind {
    case safety(SafetyLevel)
    case delegated

    init(for target: CleanupTarget) {
        self = target.strategy.isCleanable ? .safety(target.safety) : .delegated
    }

    var title: String {
        switch self {
        case .safety(let level): level.title
        case .delegated: localized("badge.delegated.title", defaultValue: "Handled by tool")
        }
    }

    var color: Color {
        switch self {
        case .safety(let level): level.color
        case .delegated: Theme.delegated
        }
    }

    var explanation: String {
        switch self {
        case .safety(let level): level.explanation
        case .delegated: localized(
            "badge.delegated.explanation",
            defaultValue: "Reclaim measures this but leaves removal to the tool that owns it."
        )
        }
    }
}

// MARK: - Color helpers

extension Color {
    /// `Color(hex: 0x1E1E21)` — sRGB, full opacity.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Byte formatting

extension Int64 {
    /// Compact size like the design: "34.2 GB" at gigabyte scale,
    /// whole megabytes below that, "—"-friendly zero handling is the
    /// caller's business. Numbers follow the current locale ("34,2 GB"
    /// in Norwegian); units come from the catalogues.
    var formattedBytesCompact: String {
        let gb = Double(self) / 1_000_000_000
        if gb >= 1 {
            let value = gb.formatted(.number.precision(.fractionLength(1)))
            return localized("format.valueGigabytes", defaultValue: "\(value) GB")
        }
        let mb = Int((Double(self) / 1_000_000).rounded())
        if mb >= 1 {
            return localized("format.valueMegabytes", defaultValue: "\(mb.formatted()) MB")
        }
        return localized("format.underOneMegabyte", defaultValue: "< 1 MB")
    }

    /// Split value/unit for hero numerals ("34.2", "GB").
    var byteParts: (value: String, unit: String) {
        let gb = Double(self) / 1_000_000_000
        if gb >= 1 {
            return (
                gb.formatted(.number.precision(.fractionLength(1))),
                localized("format.unitGigabytes", defaultValue: "GB")
            )
        }
        let mb = Int((Double(self) / 1_000_000).rounded())
        return (mb.formatted(), localized("format.unitMegabytes", defaultValue: "MB"))
    }

    /// Whole-gigabyte figure for disk capacity labels ("372 GB").
    var wholeGB: String {
        localized("format.valueGigabytes", defaultValue: "\(wholeGBValue) GB")
    }

    /// Whole-gigabyte number alone ("372"), for hero numerals.
    var wholeGBValue: String {
        (Double(self) / 1_000_000_000).rounded()
            .formatted(.number.precision(.fractionLength(0)))
    }
}
