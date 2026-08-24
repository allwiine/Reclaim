//
//  InspectorPanel+Header.swift
//  Reclaim
//
//  The panel's size headline and the file-path chip that reveals a
//  target's location in Finder.
//

import AppKit
import ReclaimKit
import SwiftUI

extension InspectorPanel {
    // MARK: - Pieces

    @ViewBuilder
    func sizeHeadline(_ status: TargetStatus) -> some View {
        switch status {
        case .measured(let measurement, _, _):
            let parts = measurement.bytes.byteParts
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s5) {
                Text(parts.value)
                    .font(Theme.heroNumber(27))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(Theme.smooth, value: measurement.bytes)
                Text(parts.unit)
                    .themeFont(.panelHeroUnit)
                    .foregroundStyle(Theme.textSecondary)
            }
        case .unmeasurable:
            Text(localized("inspector.sizeKnownAfterCleaning", defaultValue: "Size known after cleaning"))
                .themeFont(.cardTitle)
                .foregroundStyle(Theme.textSecondary)
        case .notInstalled:
            Text(localized("status.notInstalled", defaultValue: "Not installed"))
                .themeFont(.cardTitle)
                .foregroundStyle(Theme.textSecondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .themeFont(.body)
                .foregroundStyle(Theme.dangerWarn)
        case .idle, .scanning:
            Text(verbatim: "—")
                .themeFont(.cardTitle)
                .foregroundStyle(Theme.textQuaternary)
        }
    }

    func pathChip(for target: CleanupTarget, status: TargetStatus) -> some View {
        let path = status.resolvedPaths.first?.path
            .replacingOccurrences(
                of: FileManager.default.homeDirectoryForCurrentUser.path,
                with: "~"
            )
            ?? target.pathPatterns.first
            ?? ""

        return Button {
            if let url = status.resolvedPaths.first {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } label: {
            HStack(spacing: Theme.Space.s8) {
                Text(path.isEmpty
                    ? localized("inspector.noFixedLocation", defaultValue: "No fixed location")
                    : path)
                    .font(Theme.mono())
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.leading)
                if !status.resolvedPaths.isEmpty {
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.forward.square")
                        .themeFont(.revealIcon)
                        .foregroundStyle(Theme.textQuaternary)
                }
            }
            .padding(.horizontal, Theme.Space.s10)
            .padding(.vertical, Theme.Space.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.pathChipFill, in: RoundedRectangle(cornerRadius: Theme.radiusChip))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusChip)
                    .strokeBorder(Theme.pathChipStroke, lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusChip))
        }
        .buttonStyle(.plain)
        .disabled(status.resolvedPaths.isEmpty)
        .help(status.resolvedPaths.isEmpty
            ? ""
            : localized("action.revealInFinder", defaultValue: "Reveal in Finder"))
    }
}
