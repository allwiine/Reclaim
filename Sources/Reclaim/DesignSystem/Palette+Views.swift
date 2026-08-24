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
    /// Category chip label text; also used for compact table-row values
    /// (history row date column), Settings path rows, and Confirm trash
    /// toggle.
    static let textChipLabel = Color(hex: 0xC8C8CF)
    /// Search field icon glyph color (toolbar).
    static let textSearchIcon = Color(hex: 0x8B8B92)
    /// Monospaced current-path text during scan/clean progress.
    static let textProgressPath = Color(hex: 0x7E7E85)
    /// Unit label beside the not-yet-measured sidebar placeholder.
    static let textPlaceholderUnit = Color(hex: 0x5C5C63)
    /// Explanatory paragraph copy (confirm sheet body, inspector
    /// summary).
    static let textParagraph = Color(hex: 0xA8A8AF)
    /// Text on the destructive/caution warning banner (confirm sheet).
    static let textDangerBanner = Color(hex: 0xE8C9C6)
    /// Command text inside the inline snippet chip (delegated-tool
    /// card).
    static let textCommandSnippet = Color(hex: 0xDCDCE2)

    // MARK: - Fills & strokes

    /// Resting background for handled-by-tool callouts.
    static let calloutFill = Color.black.opacity(0.22)
    /// Hover background for handled-by-tool callouts.
    static let calloutFillHovered = Color.black.opacity(0.32)
    /// Border on handled-by-tool callouts.
    static let calloutStroke = Color.white.opacity(0.06)
    /// Quieter row-hover fill (biggest-locations rows).
    static let hoverFillQuiet = Color.white.opacity(0.05)
    /// Faintest row-hover fill (history table rows).
    static let hoverFillFaint = Color.white.opacity(0.04)
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
    /// Faint background wash for toolbar/footer chrome and quiet
    /// detail panels (history detail pane).
    static let chromeFill = Color.white.opacity(0.02)
    /// Divider between a scrollable body and pinned footer/header
    /// chrome (sidebar footer separator, history table header).
    static let dividerStrong = Color.white.opacity(0.08)
    /// Quieter control fill (history detail close button), below
    /// `controlFill`.
    static let controlFillQuiet = Color.white.opacity(0.07)
    /// Quieter selected-row fill (history table), below `selectionFill`.
    static let selectionFillQuiet = Color.white.opacity(0.06)
    /// Background fill behind the not-yet-measured striped placeholder.
    static let placeholderFill = Color.white.opacity(0.025)
    /// Search field border, resting.
    static let searchFieldStroke = Color.white.opacity(0.06)
    /// Search field border, focused.
    static let searchFieldStrokeFocused = Color.white.opacity(0.2)
    /// Row hover fill for target/project rows (TargetRow,
    /// ProjectsLinkRow).
    static let hoverFillRow = Color.white.opacity(0.055)
    /// Fill for the browser's inspected row (TargetRow).
    static let selectionFillInspected = Color.white.opacity(0.075)
    /// Border stroke on floating surfaces and compact controls (confirm
    /// sheet, checkbox).
    static let borderFloating = Color.white.opacity(0.14)
    /// Dimmed backdrop behind a floating sheet (confirm).
    static let sheetScrim = Color.black.opacity(0.42)
    /// Drop shadow under the floating confirm sheet.
    static let sheetShadow = Color.black.opacity(0.6)
    /// Background for the confirm sheet's scrollable item-list card.
    static let listCardFill = Color.black.opacity(0.25)
    /// Border stroke on the confirm sheet's item-list card.
    static let listCardStroke = Color.white.opacity(0.07)
    /// Background for the inline command snippet on the delegated-tool
    /// card.
    static let codeSnippetFill = Color.black.opacity(0.35)
    /// Background fill for the path-reveal chip (inspector panels).
    static let pathChipFill = Color.white.opacity(0.05)
    /// Border stroke on the path-reveal chip (inspector panels).
    static let pathChipStroke = Color.white.opacity(0.06)
}
