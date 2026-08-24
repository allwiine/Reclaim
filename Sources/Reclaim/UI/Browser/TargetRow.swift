//
//  TargetRow.swift
//  Reclaim
//
//  One target row: checkbox, name + badge + path, size + relative bar.
//

import AppKit
import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct TargetRow: View {
    @Environment(TargetResultsModel.self) private var results
    @Environment(SelectionModel.self) private var selection
    let target: CleanupTarget
    let isInspected: Bool
    let maxBytes: Int64
    let inspect: () -> Void

    private var status: TargetStatus { results.status(of: target.id) }

    var body: some View {
        Button(action: inspect) {
            HStack(spacing: 12) {
                checkbox

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(target.name)
                            .scaledFont(size: 13.5, weight: .medium)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Badge(for: target)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(target.pathPatterns.first ?? commandDisplay)
                            .font(Theme.mono())
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                        if let note = partialNote {
                            Text(note)
                                .scaledFont(size: 10.5, weight: .medium)
                                .foregroundStyle(Theme.accentLabel)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 10)

                trailing
                    .frame(width: 96, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                isInspected ? Color.white.opacity(0.075) : .clear,
                in: RoundedRectangle(cornerRadius: Theme.radiusInset)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusInset))
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: Theme.radiusInset, color: Color.white.opacity(0.055))
        .animation(Theme.quick, value: isInspected)
        .contextMenu { contextMenu }
    }

    private var commandDisplay: String {
        if case .command(let spec) = target.strategy { return spec.displayCommand }
        return ""
    }

    /// "2 of 8 items · 1.2 GB" while the target is cherry-picked.
    private var partialNote: String? {
        guard let counts = selection.partialSelectionCounts(of: target) else { return nil }
        let scope = localized(
            "format.itemsOf",
            defaultValue: "\(counts.selected) of \(counts.total) items"
        )
        let size = selection.selectedBytes(of: target).formattedBytesCompact
        return localized("browser.partialNote", defaultValue: "\(scope) · \(size)")
    }

    private var checkbox: some View {
        Toggle(
            localized("browser.selectAccessibility", defaultValue: "Select \(target.name)"),
            isOn: Binding(
                get: { selection.isSelected(target) },
                set: { selection.setSelected(target, $0) }
            )
        )
        .toggleStyle(CheckboxToggleStyle(mixed: selection.isPartiallySelected(target)))
        .labelsHidden()
        .disabled(!selection.isSelectable(target))
        .opacity(selection.isSelectable(target) ? 1 : 0.35)
    }

    @ViewBuilder
    private var trailing: some View {
        switch status {
        case .measured(let measurement, _, _):
            if measurement.bytes == 0 && measurement.inaccessibleItems == 0 {
                statusText(localized("status.empty", defaultValue: "Empty"))
            } else {
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 4) {
                        if measurement.inaccessibleItems > 0 {
                            Image(systemName: "lock")
                                .scaledFont(size: 9)
                                .foregroundStyle(Theme.caution)
                                .help(localized(
                                    "browser.unreadableEntriesHelp",
                                    defaultValue: "\(measurement.inaccessibleItems) entries could not be read — the size is a lower bound."
                                ))
                        }
                        Text(measurement.bytes.formattedBytesCompact)
                            .scaledFont(size: 13, weight: .medium)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                            .animation(Theme.smooth, value: measurement.bytes)
                    }
                    MiniBar(
                        fraction: maxBytes > 0
                            ? Double(measurement.bytes) / Double(maxBytes) : 0,
                        color: BadgeKind(for: target).color
                    )
                }
            }
        case .idle:
            statusText("—")
        case .scanning:
            ProgressView().controlSize(.small)
        case .notInstalled:
            statusText(localized("status.notInstalled", defaultValue: "Not installed"))
        case .unmeasurable:
            statusText(localized("status.sizeUnknown", defaultValue: "Size unknown"))
                .help(localized(
                    "status.sizeUnknownHelp",
                    defaultValue: "The reclaimable size is only known after cleaning."
                ))
        case .failed:
            Label(
                localized("status.scanFailed", defaultValue: "Couldn't scan"),
                systemImage: "exclamationmark.triangle"
            )
            .themeFont(.caption)
            .foregroundStyle(Theme.dangerWarn)
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .scaledFont(size: 12)
            .foregroundStyle(Theme.textTertiary)
    }

    @ViewBuilder
    private var contextMenu: some View {
        let paths = status.resolvedPaths
        if let first = paths.first {
            Button(localized("action.revealInFinder", defaultValue: "Reveal in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([first])
            }
            Button(localized("browser.copyPaths", defaultValue: "Copy \(paths.count) Paths")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    paths.map(\.path).joined(separator: "\n"),
                    forType: .string
                )
            }
        }
        if target.strategy.isCleanable {
            if !paths.isEmpty { Divider() }
            Toggle(
                localized("browser.keepOutOfAutoSelect", defaultValue: "Keep out of automatic selection"),
                isOn: Binding(
                    get: { selection.isExcludedFromAutoSelect(target) },
                    set: { selection.setExcludedFromAutoSelect(target, $0) }
                )
            )
        }
    }
}
