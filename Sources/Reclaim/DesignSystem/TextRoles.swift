//
//  TextRoles.swift
//  Reclaim
//
//  `Theme.TextRole` — moved out of ScaledFont.swift to stay under its
//  200-code-line budget. Applied through `.themeFont(_:)`; the Dynamic
//  Type plumbing (the view modifiers and `themeFont`/`scaledFont`
//  helpers) still lives in ScaledFont.swift.
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
        /// Content column toolbar title.
        case toolbarTitle
        /// Scan/refresh icon glyph (toolbar).
        case refreshIcon
        /// Search field icon glyphs (magnifying glass, clear button).
        case searchIcon
        /// Full-screen scan/clean phase headline ("Scanning", "Moving
        /// to Trash").
        case phaseHeadline
        /// Unit label beside a hero stat number (scan found-so-far,
        /// history lifetime total).
        case statUnit
        /// Empty-state glyph (history's "No cleans yet").
        case emptyStateIcon
        /// Empty-state title text.
        case emptyStateTitle
        /// History detail pane's header date title.
        case detailHeaderTitle
        /// Unit label beside the history detail hero number
        /// ("GB freed").
        case detailHeroUnit
        /// Sidebar navigation row icon glyph.
        case navIcon
        /// Unit label beside the sidebar "Reclaimable" hero number.
        case sidebarUnit
        /// Small note beside a row's path noting partial selection
        /// (browser rows).
        case partialNote
        /// Inaccessible-items lock glyph (browser rows).
        case lockIcon
        /// Inspector panel's item-name headline (target/project).
        case panelTitle
        /// Small text-button label (Copy, Select all/Deselect all).
        case miniButtonLabel
        /// Unit label beside the inspector panel's hero byte number
        /// (target/project).
        case panelHeroUnit
        /// Reveal-in-Finder arrow glyph on the path chip (inspector
        /// panels).
        case revealIcon
        /// Project inspector's folder-tile icon glyph.
        case projectTileIcon
        /// Confirm sheet's small checkbox checkmark glyph.
        case checkmarkIcon
        /// Confirm sheet's headline title.
        case sheetTitle
        /// Icon above the Projects screen's "add a dev folder" prompt.
        case emptyPromptIcon
        /// Headline of the Projects screen's "add a dev folder" prompt.
        case emptyPromptTitle

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
            case .toolbarTitle: 13
            case .refreshIcon: 10
            case .searchIcon: 10
            case .phaseHeadline: 20
            case .statUnit: 15
            case .emptyStateIcon: 28
            case .emptyStateTitle: 14
            case .detailHeaderTitle: 16
            case .detailHeroUnit: 14
            case .navIcon: 10.5
            case .sidebarUnit: 15
            case .partialNote: 10.5
            case .lockIcon: 9
            case .panelTitle: 17
            case .miniButtonLabel: 11
            case .panelHeroUnit: 13
            case .revealIcon: 10
            case .projectTileIcon: 15
            case .checkmarkIcon: 8.5
            case .sheetTitle: 15
            case .emptyPromptIcon: 34
            case .emptyPromptTitle: 16
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
            case .toolbarTitle, .phaseHeadline, .detailHeaderTitle: .semibold
            case .refreshIcon, .emptyStateTitle, .navIcon, .sidebarUnit: .medium
            case .searchIcon, .statUnit, .emptyStateIcon, .detailHeroUnit: .regular
            case .partialNote, .miniButtonLabel: .medium
            case .lockIcon, .panelHeroUnit, .revealIcon: .regular
            case .panelTitle, .sheetTitle, .checkmarkIcon: .bold
            case .projectTileIcon: .semibold
            case .emptyPromptIcon: .light
            case .emptyPromptTitle: .semibold
            }
        }
    }
}
