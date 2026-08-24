//
//  BrowserView+SelectionStrip.swift
//  Reclaim
//
//  The strip above the list: select-all-safe, clear, and a running
//  count of what's selected among the currently visible targets.
//

import ReclaimAppCore
import SwiftUI

extension BrowserView {
    // MARK: - Selection strip

    var selectionStrip: some View {
        HStack(spacing: 10) {
            Button(localized("browser.selectAllSafe", defaultValue: "Select all safe")) {
                selection.selectAllSafe()
            }
            .buttonStyle(StripChipButtonStyle())

            Button(localized("browser.clear", defaultValue: "Clear")) {
                selection.clear()
            }
            .buttonStyle(StripChipButtonStyle(plain: true))
            .disabled(selection.ids.isEmpty)

            Spacer()

            Text(selectionSummary)
                .scaledFont(size: 12)
                .monospacedDigit()
                .foregroundStyle(Theme.textLabel)
                .contentTransition(.numericText())
                .animation(Theme.smooth, value: selection.ids.count)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    /// Scoped to the list it sits above: counting selections the user
    /// cannot see here reads as a lie ("4 selected" over an unticked
    /// list). The global size lives on the toolbar's Reclaim button.
    private var selectionSummary: String {
        let visible = visibleTargets
        let pickedHere = visible.count { selection.isSelected($0) }
        guard pickedHere > 0 else {
            return localized("browser.noItemsSelected", defaultValue: "No items selected")
        }
        let selectable = selection.selectableItemCount(among: visible)
        let bytes = visible.reduce(Int64(0)) { $0 + selection.selectedBytes(of: $1) }
        return localized(
            "browser.selectionSummary",
            defaultValue: "\(pickedHere) of \(selectable) items selected · \(bytes.formattedBytesCompact)"
        )
    }
}
