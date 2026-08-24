//
//  Palette+Views.swift
//  Reclaim
//
//  View-local colors identified while routing the dashboard screens
//  (Overview, Idle, Done) through the DesignSystem — named for their
//  role, value-identical to the literals they replaced.
//

import SwiftUI

extension Theme {
    // MARK: - Text

    /// Row/legend name text — dimmer than primary, brighter than
    /// secondary (disk legend, project rows).
    static let textRowLabel = Color(hex: 0xB4B4BB)
    /// Category grid tile title text.
    static let textCategoryTitle = Color(hex: 0xD5D5DB)
    /// Subtle secondary text (project-row icon, failure list copy).
    static let textSubtle = Color(hex: 0xB8B8BF)
    /// Category chip label text.
    static let textChipLabel = Color(hex: 0xC8C8CF)

    // MARK: - Fills & strokes

    /// Resting background for handled-by-tool callouts.
    static let calloutFill = Color.black.opacity(0.22)
    /// Hover background for handled-by-tool callouts.
    static let calloutFillHovered = Color.black.opacity(0.32)
    /// Border on handled-by-tool callouts.
    static let calloutStroke = Color.white.opacity(0.06)
    /// Quieter row-hover fill (biggest-locations rows).
    static let hoverFillQuiet = Color.white.opacity(0.05)
    /// "Other used space" meter fill on disk cards.
    static let usedTrack = Color.white.opacity(0.28)
    /// Used-space fill on the pre-scan idle footer.
    static let usedTrackIdle = Color.white.opacity(0.22)
    /// Divider beneath a card's header section.
    static let cardSectionDivider = Color.white.opacity(0.07)
    /// Divider between a card's lower sections.
    static let cardSectionDividerFaint = Color.white.opacity(0.05)
    /// Drop shadow under elevated cards (catalogue card).
    static let cardShadow = Color.black.opacity(0.4)
    /// Category chip background.
    static let chipFill = Color.white.opacity(0.03)
    /// Category chip border.
    static let chipStroke = Color.white.opacity(0.05)
    /// "+N more" chip background.
    static let moreChipFill = Color.white.opacity(0.02)
    /// "+N more" chip border.
    static let moreChipStroke = Color.white.opacity(0.04)
    /// Divider between rows in the Done screen's lists.
    static let rowDivider = Color.white.opacity(0.06)
}
