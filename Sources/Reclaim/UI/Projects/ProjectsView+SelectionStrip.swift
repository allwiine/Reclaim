//
//  ProjectsView+SelectionStrip.swift
//  Reclaim
//
//  The strip above the list: sort order, select-all/clear for
//  artifacts, a running selection count, and the add-folder button.
//

import ReclaimAppCore
import SwiftUI

extension ProjectsView {
    // MARK: - Strip

    var strip: some View {
        HStack(spacing: 10) {
            Picker(localized("projects.sortLabel", defaultValue: "Sort"), selection: $sortOrder) {
                Text(localized("projects.sortBySize", defaultValue: "Largest first"))
                    .tag(SortOrder.bySize)
                Text(localized("projects.sortByActivity", defaultValue: "Longest inactive first"))
                    .tag(SortOrder.byActivity)
            }
            .pickerStyle(.menu)
            .fixedSize()

            Button(localized("projects.selectAllArtifacts", defaultValue: "Select all")) {
                projects.selectAllArtifacts()
            }
            .buttonStyle(StripChipButtonStyle())
            .disabled(activity.isScanning || activity.isCleaning || projects.selectableArtifactCount == 0)

            Button(localized("browser.clear", defaultValue: "Clear")) {
                projects.clearArtifactSelection()
            }
            .buttonStyle(StripChipButtonStyle(plain: true))
            .disabled(projects.selectedArtifacts.isEmpty)

            Spacer()

            Text(selectionSummary)
                .scaledFont(size: 12)
                .monospacedDigit()
                .foregroundStyle(Theme.textLabel)
                .contentTransition(.numericText())
                .animation(Theme.smooth, value: projects.selectedArtifactBytes)

            Button(localized("projects.addFolder", defaultValue: "Add a development folder…")) {
                for url in DevFolderPicker.pickFolders() {
                    projects.addDevRoot(url)
                }
            }
            .rcSecondary()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    /// Scoped to the artifacts this screen lists — never the registry
    /// selection (that count lives in the category browser).
    private var selectionSummary: String {
        let picked = projects.selectedArtifacts.count
        guard picked > 0 else {
            return localized("browser.noItemsSelected", defaultValue: "No items selected")
        }
        return localized(
            "browser.selectionSummary",
            defaultValue: "\(picked) of \(projects.selectableArtifactCount) items selected · \(projects.selectedArtifactBytes.formattedBytesCompact)"
        )
    }
}
