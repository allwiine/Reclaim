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
            let entries = model.breakdowns.entries[target.id] ?? []

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                SectionLabel(localized("inspector.largestContents", defaultValue: "Largest contents"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if pickable, !entries.isEmpty {
                    Button(model.selection.isSelected(target) && !model.selection.isPartiallySelected(target)
                        ? localized("inspector.deselectAllContents", defaultValue: "Deselect all")
                        : localized("inspector.selectAllContents", defaultValue: "Select all")
                    ) {
                        model.selection.setSelected(
                            target,
                            !(model.selection.isSelected(target) && !model.selection.isPartiallySelected(target))
                        )
                    }
                    .buttonStyle(.plain)
                    .scaledFont(size: 11, weight: .medium)
                    .foregroundStyle(Theme.textSecondary)
                    .disabled(model.activity.isScanning || model.activity.isCleaning)
                }
            }
            .padding(.top, 24)

            if !entries.isEmpty {
                let cleanupPathSet = Set(cleanupPaths.map(\.path))
                let shown = showAllContents ? entries : Array(entries.prefix(5))
                let peak = entries.map(\.bytes).max() ?? 1
                VStack(spacing: 1) {
                    ForEach(shown) { entry in
                        contentRow(
                            entry, for: target, peak: peak,
                            pickable: pickable && cleanupPathSet.contains(entry.id)
                        )
                    }
                }
                .padding(.top, 9)
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
                    .scaledFont(size: 11.5, weight: .medium)
                    .foregroundStyle(Theme.accentLabel)
                    .padding(.top, 10)
                }

                if pickable {
                    cherryPickFooter(for: target)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(localized("inspector.measuringContents", defaultValue: "Measuring contents…"))
                        .themeFont(.caption)
                        .foregroundStyle(Theme.textQuaternary)
                }
                .padding(.top, 12)
            }
        }
    }

    private func contentRow(
        _ entry: BreakdownEntry, for target: CleanupTarget, peak: Int64, pickable: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 9) {
                if pickable {
                    Toggle(
                        localized("browser.selectAccessibility", defaultValue: "Select \(entry.name)"),
                        isOn: Binding(
                            get: { model.selection.isPathSelected(target, path: entry.id) },
                            set: { model.selection.setPathSelected(target, path: entry.id, $0) }
                        )
                    )
                    .toggleStyle(CheckboxToggleStyle(size: 15))
                    .labelsHidden()
                    .disabled(model.activity.isScanning || model.activity.isCleaning)
                }
                Text(entry.name)
                    .scaledFont(size: 12)
                    .foregroundStyle(
                        entry.itemCount > 1 ? Theme.textTertiary : Theme.textPrimary
                    )
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(entry.bytes.formattedBytesCompact)
                    .themeFont(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: 0x8E8E95))
            }
            MiniBar(
                fraction: peak > 0 ? Double(entry.bytes) / Double(peak) : 0,
                color: target.category.color
            )
            .padding(.leading, pickable ? 24 : 0)
        }
        .padding(.vertical, 7)
        .transition(.opacity)
    }

    /// Cherry-pick status line plus the "Clean just this" button.
    @ViewBuilder
    private func cherryPickFooter(for target: CleanupTarget) -> some View {
        Text(pickNote(for: target))
            .themeFont(.caption)
            .foregroundStyle(Theme.textQuaternary)
            .padding(.top, 9)

        Button {
            onCleanSingle(target)
        } label: {
            Text(cleanJustThisLabel(for: target))
                .frame(maxWidth: .infinity)
        }
        .rcPrimary()
        .disabled(!model.selection.isSelected(target) || model.activity.isScanning || model.activity.isCleaning)
        .padding(.top, 12)
    }

    private func scopeLabel(for target: CleanupTarget) -> String? {
        guard let counts = model.selection.partialSelectionCounts(of: target) else { return nil }
        return localized(
            "format.itemsOf",
            defaultValue: "\(counts.selected) of \(counts.total) items"
        )
    }

    private func pickNote(for target: CleanupTarget) -> String {
        guard let scope = scopeLabel(for: target) else {
            return localized("inspector.tickHint", defaultValue: "Tick items to clean only those")
        }
        let size = model.selection.selectedBytes(of: target).formattedBytesCompact
        return localized("inspector.tickedNote", defaultValue: "\(scope) ticked · \(size)")
    }

    private func cleanJustThisLabel(for target: CleanupTarget) -> String {
        guard model.selection.isSelected(target) else {
            return localized("inspector.nothingTicked", defaultValue: "Nothing ticked here")
        }
        let size = model.selection.selectedBytes(of: target).formattedBytesCompact
        guard let scope = scopeLabel(for: target) else {
            return localized("inspector.cleanJustThis", defaultValue: "Clean just this · \(size)")
        }
        return localized("inspector.cleanPartial", defaultValue: "Clean \(scope) · \(size)")
    }
}
