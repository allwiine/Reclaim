//
//  InspectorPanel+Breakdown.swift
//  Reclaim
//
//  The "Largest contents" list: per-item rows with cherry-pick
//  toggles, the show-more control, and the "Clean just this" footer.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension InspectorPanel {
    @ViewBuilder
    func breakdown(for target: CleanupTarget, status: TargetStatus) -> some View {
        if case .measured(let measurement, _, let cleanupPaths) = status, measurement.bytes > 0 {
            let pickable = target.strategy.isCleanable && !cleanupPaths.isEmpty
            let entries = breakdowns.entries[target.id] ?? []

            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s10) {
                SectionLabel(localized("inspector.largestContents", defaultValue: "Largest contents"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if pickable, !entries.isEmpty {
                    Button(selection.isSelected(target) && !selection.isPartiallySelected(target)
                        ? localized("inspector.deselectAllContents", defaultValue: "Deselect all")
                        : localized("inspector.selectAllContents", defaultValue: "Select all")
                    ) {
                        selection.setSelected(
                            target,
                            !(selection.isSelected(target) && !selection.isPartiallySelected(target))
                        )
                    }
                    .buttonStyle(.plain)
                    .themeFont(.miniButtonLabel)
                    .foregroundStyle(Theme.textSecondary)
                    .disabled(activity.isScanning || activity.isCleaning)
                }
            }
            .padding(.top, Theme.Space.s24)

            if !entries.isEmpty {
                let cleanupPathSet = Set(cleanupPaths.map(\.path))
                let shown = showAllContents ? entries : Array(entries.prefix(5))
                let peak = entries.map(\.bytes).max() ?? 1
                VStack(spacing: Theme.Space.s1) {
                    ForEach(shown) { entry in
                        contentRow(
                            entry, for: target, peak: peak,
                            pickable: pickable && cleanupPathSet.contains(entry.id)
                        )
                    }
                }
                .padding(.top, Theme.Space.s9)
                .animation(Theme.smooth, value: entries)

                if entries.count > 5 {
                    Button(showAllContents
                        ? localized("inspector.showTop5", defaultValue: "Show top 5 only")
                        : localized(
                            "inspector.showAllContents",
                            defaultValue: "Show all \(entries.count) items"
                        )
                    ) {
                        withAnimation(Theme.quick) { showAllContents.toggle() }
                    }
                    .buttonStyle(.plain)
                    .themeFont(.chipLabel)
                    .foregroundStyle(Theme.accentLabel)
                    .padding(.top, Theme.Space.s10)
                }

                if pickable {
                    cherryPickFooter(for: target)
                }
            } else {
                HStack(spacing: Theme.Space.s8) {
                    ProgressView().controlSize(.small)
                    Text(localized("inspector.measuringContents", defaultValue: "Measuring contents…"))
                        .themeFont(.caption)
                        .foregroundStyle(Theme.textQuaternary)
                }
                .padding(.top, Theme.Space.s12)
            }
        }
    }

    private func contentRow(
        _ entry: BreakdownEntry, for target: CleanupTarget, peak: Int64, pickable: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s5) {
            HStack(alignment: .center, spacing: Theme.Space.s9) {
                if pickable {
                    Toggle(
                        localized("browser.selectAccessibility", defaultValue: "Select \(entry.name)"),
                        isOn: Binding(
                            get: { selection.isPathSelected(target, path: entry.id) },
                            set: { selection.setPathSelected(target, path: entry.id, $0) }
                        )
                    )
                    .toggleStyle(CheckboxToggleStyle(size: 15))
                    .labelsHidden()
                    .disabled(activity.isScanning || activity.isCleaning)
                }
                Text(entry.name)
                    .themeFont(.meta)
                    .foregroundStyle(
                        entry.itemCount > 1 ? Theme.textTertiary : Theme.textPrimary
                    )
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(entry.bytes.formattedBytesCompact)
                    .themeFont(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            MiniBar(
                fraction: peak > 0 ? Double(entry.bytes) / Double(peak) : 0,
                color: target.category.color
            )
            .padding(.leading, pickable ? Theme.Space.s24 : Theme.Space.s0)
        }
        .padding(.vertical, Theme.Space.s7)
        .transition(.opacity)
    }

    /// Cherry-pick status line plus the "Clean just this" button.
    @ViewBuilder
    private func cherryPickFooter(for target: CleanupTarget) -> some View {
        Text(pickNote(for: target))
            .themeFont(.caption)
            .foregroundStyle(Theme.textQuaternary)
            .padding(.top, Theme.Space.s9)

        Button {
            onCleanSingle(target)
        } label: {
            Text(cleanJustThisLabel(for: target))
                .frame(maxWidth: .infinity)
        }
        .rcPrimary()
        .disabled(!selection.isSelected(target) || activity.isScanning || activity.isCleaning)
        .padding(.top, Theme.Space.s12)
    }

    private func scopeLabel(for target: CleanupTarget) -> String? {
        guard let counts = selection.partialSelectionCounts(of: target) else { return nil }
        return localized(
            "format.itemsOf",
            defaultValue: "\(counts.selected) of \(counts.total) items"
        )
    }

    private func pickNote(for target: CleanupTarget) -> String {
        guard let scope = scopeLabel(for: target) else {
            return localized("inspector.tickHint", defaultValue: "Tick items to clean only those")
        }
        let size = selection.selectedBytes(of: target).formattedBytesCompact
        return localized("inspector.tickedNote", defaultValue: "\(scope) ticked · \(size)")
    }

    private func cleanJustThisLabel(for target: CleanupTarget) -> String {
        guard selection.isSelected(target) else {
            return localized("inspector.nothingTicked", defaultValue: "Nothing ticked here")
        }
        let size = selection.selectedBytes(of: target).formattedBytesCompact
        guard let scope = scopeLabel(for: target) else {
            return localized("inspector.cleanJustThis", defaultValue: "Clean just this · \(size)")
        }
        return localized("inspector.cleanPartial", defaultValue: "Clean \(scope) · \(size)")
    }
}
