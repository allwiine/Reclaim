//
//  InspectorPanel.swift
//  Reclaim
//
//  The browser's detail column: what a target is, what cleaning costs,
//  where the space actually sits, and — for tool-managed items — the
//  command that reclaims it.
//

import AppKit
import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct InspectorPanel: View {
    @Environment(AppModel.self) private var model
    let target: CleanupTarget?
    /// Opens the single-target clean confirmation ("Clean just this").
    var onCleanSingle: (CleanupTarget) -> Void = { _ in }

    @State private var copied = false
    /// Expands the contents list past the top five. These live on the
    /// panel, whose identity is stable across target changes, so the
    /// `.id(target.id)` on the inner ScrollView does not reset them —
    /// the `.task(id:)` in `details(for:)` does.
    @State private var showAllContents = false

    var body: some View {
        Group {
            if let target {
                details(for: target)
            } else {
                Text(localized("inspector.selectAnItem", defaultValue: "Select an item"))
                    .themeFont(.body)
                    .foregroundStyle(Theme.textQuaternary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.white.opacity(0.02))
    }

    private func details(for target: CleanupTarget) -> some View {
        let status = model.status(of: target.id)

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CategoryTile(category: target.category, size: 34)

                Text(target.name)
                    .scaledFont(size: 17, weight: .bold)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 14)

                HStack(spacing: 8) {
                    Badge(for: target)
                    Text(target.category.title)
                        .scaledFont(size: 12)
                        .foregroundStyle(Color(hex: 0x8E8E95))
                }
                .padding(.top, 8)

                sizeHeadline(status)
                    .padding(.top, 16)

                Text(target.summary)
                    .themeFont(.body)
                    .lineSpacing(3.5)
                    .foregroundStyle(Color(hex: 0xA8A8AF))
                    .padding(.top, 14)

                if let note = target.note {
                    Label(note, systemImage: "info.circle")
                        .themeFont(.caption)
                        .lineSpacing(2.5)
                        .foregroundStyle(
                            target.safety == .safe ? Theme.textTertiary : Theme.cautionTitle
                        )
                        .padding(.top, 10)
                }

                if target.strategy.isCleanable, model.isExcludedFromAutoSelect(target) {
                    Label(
                        localized(
                            "inspector.excludedNote",
                            defaultValue: "Kept out of automatic selection — tick it manually to clean it."
                        ),
                        systemImage: "hand.raised"
                    )
                    .themeFont(.caption)
                    .lineSpacing(2.5)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 10)
                }

                pathChip(for: target, status: status)
                    .padding(.top, 14)

                if !target.strategy.isCleanable {
                    delegatedCard(for: target)
                        .padding(.top, 16)
                }

                if case .command(let spec) = target.strategy {
                    commandInfo(spec)
                        .padding(.top, 14)
                }

                breakdown(for: target, status: status)

                footer(status)
                    .padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(target.id)
        .task(id: target.id) {
            // Reset per-target view state that lives on the (stable) panel.
            showAllContents = false
            copied = false
            model.loadBreakdown(for: target)
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func sizeHeadline(_ status: TargetStatus) -> some View {
        switch status {
        case .measured(let measurement, _, _):
            let parts = measurement.bytes.byteParts
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(parts.value)
                    .font(Theme.heroNumber(27))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(Theme.smooth, value: measurement.bytes)
                Text(parts.unit)
                    .scaledFont(size: 13)
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

    private func pathChip(for target: CleanupTarget, status: TargetStatus) -> some View {
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
            HStack(spacing: 8) {
                Text(path.isEmpty
                    ? localized("inspector.noFixedLocation", defaultValue: "No fixed location")
                    : path)
                    .font(Theme.mono())
                    .foregroundStyle(Color(hex: 0x8E8E95))
                    .multilineTextAlignment(.leading)
                if !status.resolvedPaths.isEmpty {
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.forward.square")
                        .scaledFont(size: 10)
                        .foregroundStyle(Theme.textQuaternary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.radiusChip))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusChip)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusChip))
        }
        .buttonStyle(.plain)
        .disabled(status.resolvedPaths.isEmpty)
        .help(status.resolvedPaths.isEmpty
            ? ""
            : localized("action.revealInFinder", defaultValue: "Reveal in Finder"))
    }

    private func delegatedCard(for target: CleanupTarget) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(localized("inspector.wontDeleteTitle", defaultValue: "Reclaim won’t delete this"))
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(Theme.cautionTitle)
            Text(target.manualInstructions ?? "")
                .scaledFont(size: 12)
                .lineSpacing(3)
                .foregroundStyle(Color(hex: 0xB8B8BF))

            if let command = target.manualCommand {
                HStack(spacing: 8) {
                    Text(command)
                        .font(Theme.mono())
                        .foregroundStyle(Color(hex: 0xDCDCE2))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(copied
                        ? localized("action.copied", defaultValue: "Copied")
                        : localized("action.copy", defaultValue: "Copy")
                    ) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                        withAnimation(Theme.quick) { copied = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1.4))
                            withAnimation(Theme.quick) { copied = false }
                        }
                    }
                    .buttonStyle(.plain)
                    .scaledFont(size: 11, weight: .medium)
                    .foregroundStyle(Theme.accentLabel)
                    .contentTransition(.opacity)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                .padding(.top, 5)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.caution.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusInset))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusInset)
                .strokeBorder(Theme.caution.opacity(0.3), lineWidth: 0.5)
        }
    }

    private func commandInfo(_ spec: CommandSpec) -> some View {
        Label {
            Text(localized("inspector.cleansByRunning", defaultValue: "Cleans by running"))
                + Text(verbatim: " ")
                + Text(spec.displayCommand).font(Theme.mono())
        } icon: {
            Image(systemName: "terminal")
        }
        .themeFont(.caption)
        .foregroundStyle(Theme.textSecondary)
    }

    @ViewBuilder
    private func breakdown(for target: CleanupTarget, status: TargetStatus) -> some View {
        if case .measured(let measurement, _, let cleanupPaths) = status, measurement.bytes > 0 {
            let pickable = target.strategy.isCleanable && !cleanupPaths.isEmpty
            let entries = model.breakdowns[target.id] ?? []

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                SectionLabel(localized("inspector.largestContents", defaultValue: "Largest contents"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if pickable, !entries.isEmpty {
                    Button(model.isSelected(target) && !model.isPartiallySelected(target)
                        ? localized("inspector.deselectAllContents", defaultValue: "Deselect all")
                        : localized("inspector.selectAllContents", defaultValue: "Select all")
                    ) {
                        model.setSelected(
                            target,
                            !(model.isSelected(target) && !model.isPartiallySelected(target))
                        )
                    }
                    .buttonStyle(.plain)
                    .scaledFont(size: 11, weight: .medium)
                    .foregroundStyle(Theme.textSecondary)
                    .disabled(model.isScanning || model.isCleaning)
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
                            get: { model.isPathSelected(target, path: entry.id) },
                            set: { model.setPathSelected(target, path: entry.id, $0) }
                        )
                    )
                    .toggleStyle(CheckboxToggleStyle(size: 15))
                    .labelsHidden()
                    .disabled(model.isScanning || model.isCleaning)
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
        .disabled(!model.isSelected(target) || model.isScanning || model.isCleaning)
        .padding(.top, 12)
    }

    private func scopeLabel(for target: CleanupTarget) -> String? {
        guard let counts = model.partialSelectionCounts(of: target) else { return nil }
        return localized(
            "format.itemsOf",
            defaultValue: "\(counts.selected) of \(counts.total) items"
        )
    }

    private func pickNote(for target: CleanupTarget) -> String {
        guard let scope = scopeLabel(for: target) else {
            return localized("inspector.tickHint", defaultValue: "Tick items to clean only those")
        }
        let size = model.selectedBytes(of: target).formattedBytesCompact
        return localized("inspector.tickedNote", defaultValue: "\(scope) ticked · \(size)")
    }

    private func cleanJustThisLabel(for target: CleanupTarget) -> String {
        guard model.isSelected(target) else {
            return localized("inspector.nothingTicked", defaultValue: "Nothing ticked here")
        }
        let size = model.selectedBytes(of: target).formattedBytesCompact
        guard let scope = scopeLabel(for: target) else {
            return localized("inspector.cleanJustThis", defaultValue: "Clean just this · \(size)")
        }
        return localized("inspector.cleanPartial", defaultValue: "Clean \(scope) · \(size)")
    }

    @ViewBuilder
    private func footer(_ status: TargetStatus) -> some View {
        if case .measured(let measurement, let resolved, _) = status {
            Text(footerLine(measurement, locations: resolved.count))
                .themeFont(.caption)
                .lineSpacing(2.5)
                .foregroundStyle(Theme.textQuaternary)
        }
    }

    private func footerLine(_ measurement: DiskMeasurement, locations: Int) -> String {
        var line = localized(
            "inspector.footer",
            defaultValue: "\(measurement.fileCount) files across \(locations) locations."
        )
        if measurement.inaccessibleItems > 0 {
            line += " " + localized(
                "inspector.footerUnreadable",
                defaultValue: "\(measurement.inaccessibleItems) entries could not be read — sizes are a lower bound."
            )
        }
        return line
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Measured", traits: .fixedLayout(width: 336, height: 810)) {
    let model = PreviewData.scanned()
    return InspectorPanel(target: model.targets.first { $0.id == "xcode-derived-data" })
        .background(Theme.background)
        .environment(model)
        .preferredColorScheme(.dark)
}

#Preview("Tool-managed", traits: .fixedLayout(width: 336, height: 810)) {
    let model = PreviewData.scanned()
    return InspectorPanel(target: model.targets.first { $0.id == "docker-vm-disk" })
        .background(Theme.background)
        .environment(model)
        .preferredColorScheme(.dark)
}
#endif
