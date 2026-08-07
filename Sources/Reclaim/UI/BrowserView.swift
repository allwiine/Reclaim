//
//  BrowserView.swift
//  Reclaim
//
//  The results browser: a selectable list of a category's targets (or
//  search matches) on the left, the detail inspector on the right.
//

import AppKit
import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct BrowserView: View {
    enum Mode: Equatable {
        case category(ToolCategory)
        case search(String)
    }

    @Environment(AppModel.self) private var model
    let mode: Mode
    /// Row to anchor the inspector on when arriving from a tap on a
    /// specific target elsewhere (overview lists); `nil` falls back to
    /// the first row.
    var initialInspectedID: CleanupTarget.ID?

    @State private var inspectedID: CleanupTarget.ID?

    var body: some View {
        let targets = visibleTargets

        HStack(spacing: 0) {
            VStack(spacing: 0) {
                selectionStrip

                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)

                if targets.isEmpty {
                    emptyState
                } else {
                    list(targets)
                }
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Theme.divider)
                .frame(width: 1)

            InspectorPanel(target: inspectedTarget(in: targets))
                .frame(width: 336)
        }
        .onChange(of: mode, initial: true) { _, _ in
            // Entering a category (or refining a search) anchors the
            // inspector on the tapped target when one was passed in,
            // otherwise on the first row.
            inspectedID = initialInspectedID ?? visibleTargets.first?.id
        }
    }

    // MARK: - Data

    private var visibleTargets: [CleanupTarget] {
        switch mode {
        case .category(let category):
            return model.visibleTargets(in: category)
        case .search(let query):
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return [] }
            return model.targets.filter { target in
                target.name.localizedCaseInsensitiveContains(trimmed)
                    || target.summary.localizedCaseInsensitiveContains(trimmed)
                    || target.category.title.localizedCaseInsensitiveContains(trimmed)
                    || target.pathPatterns.contains {
                        $0.localizedCaseInsensitiveContains(trimmed)
                    }
            }
        }
    }

    private func inspectedTarget(in targets: [CleanupTarget]) -> CleanupTarget? {
        targets.first { $0.id == inspectedID } ?? targets.first
    }

    // MARK: - Selection strip

    private var selectionStrip: some View {
        HStack(spacing: 10) {
            Button(localized("browser.selectAllSafe", defaultValue: "Select all safe")) {
                model.selectAllSafe()
            }
            .buttonStyle(StripChipButtonStyle())

            Button(localized("browser.clear", defaultValue: "Clear")) {
                model.clearSelection()
            }
            .buttonStyle(StripChipButtonStyle(plain: true))
            .disabled(model.selection.isEmpty)

            Spacer()

            Text(selectionSummary)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Theme.textLabel)
                .contentTransition(.numericText())
                .animation(Theme.smooth, value: model.selection.count)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var selectionSummary: String {
        let picked = model.selection.count
        guard picked > 0 else {
            return localized("browser.noItemsSelected", defaultValue: "No items selected")
        }
        let selectable = model.selectableItemCount
        return localized(
            "browser.selectionSummary",
            defaultValue: "\(picked) of \(selectable) items selected · \(model.selectedBytes.formattedBytesCompact)"
        )
    }

    // MARK: - List

    private func list(_ targets: [CleanupTarget]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(targets) { target in
                        TargetRow(
                            target: target,
                            isInspected: inspectedTarget(in: targets)?.id == target.id,
                            maxBytes: targets.map { model.bytes(of: $0) }.max() ?? 0
                        ) {
                            inspectedID = target.id
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 20)
            }
            // A target tapped elsewhere may sit below the fold in long
            // categories — reveal it. (Rows clicked in this list are
            // already visible, so this is a no-op for them.)
            .onChange(of: inspectedID, initial: true) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: emptyIcon)
                .font(.system(size: 28))
                .foregroundStyle(Theme.textQuaternary)
            Text(emptyTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text(emptyDetail)
                .font(Theme.body)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyIcon: String {
        if case .search = mode { return "magnifyingglass" }
        return "tray"
    }

    private var emptyTitle: String {
        if case .search = mode {
            return localized("browser.noMatches", defaultValue: "No matches")
        }
        return localized("browser.nothingFound", defaultValue: "Nothing found")
    }

    private var emptyDetail: String {
        switch mode {
        case .search:
            localized(
                "browser.emptySearchDetail",
                defaultValue: "No catalogue entry matches that search — try a tool name or a path fragment."
            )
        case .category:
            localized(
                "browser.emptyCategoryDetail",
                defaultValue: "None of these tools were found on this Mac. Enable “Show tools that are not installed” in Settings to list them anyway."
            )
        }
    }
}

// MARK: - Row

/// One target row: checkbox, name + badge + path, size + relative bar.
private struct TargetRow: View {
    @Environment(AppModel.self) private var model
    let target: CleanupTarget
    let isInspected: Bool
    let maxBytes: Int64
    let inspect: () -> Void

    private var status: TargetStatus { model.status(of: target.id) }

    var body: some View {
        Button(action: inspect) {
            HStack(spacing: 12) {
                checkbox

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(target.name)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Badge(for: target)
                    }
                    Text(target.pathPatterns.first ?? commandDisplay)
                        .font(Theme.mono())
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
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

    private var checkbox: some View {
        Toggle(
            localized("browser.selectAccessibility", defaultValue: "Select \(target.name)"),
            isOn: Binding(
                get: { model.isSelected(target) },
                set: { model.setSelected(target, $0) }
            )
        )
        .toggleStyle(.rcCheckbox)
        .labelsHidden()
        .disabled(!model.isSelectable(target))
        .opacity(model.isSelectable(target) ? 1 : 0.35)
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
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.caution)
                                .help(localized(
                                    "browser.unreadableEntriesHelp",
                                    defaultValue: "\(measurement.inaccessibleItems) entries could not be read — the size is a lower bound."
                                ))
                        }
                        Text(measurement.bytes.formattedBytesCompact)
                            .font(.system(size: 13, weight: .medium))
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
            .font(Theme.caption)
            .foregroundStyle(Theme.dangerWarn)
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
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
                    get: { model.isExcludedFromAutoSelect(target) },
                    set: { model.setExcludedFromAutoSelect(target, $0) }
                )
            )
        }
    }
}

/// Small chip button for the selection strip.
private struct StripChipButtonStyle: ButtonStyle {
    var plain = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(
                plain
                    ? (isHovered && isEnabled ? Theme.textPrimary : Theme.textSecondary)
                    : Color(hex: 0xD5D5DB)
            )
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background {
                if !plain {
                    RoundedRectangle(cornerRadius: Theme.radiusChip)
                        .fill(Color.white.opacity(isHovered ? 0.12 : 0.07))
                    RoundedRectangle(cornerRadius: Theme.radiusChip)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
                }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
            .animation(Theme.quick, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Category", traits: .fixedLayout(width: 1060, height: 810)) {
    BrowserView(mode: .category(.xcode))
        .background(Theme.background)
        .environment(PreviewData.scanned())
        .preferredColorScheme(.dark)
}

#Preview("Search", traits: .fixedLayout(width: 1060, height: 810)) {
    BrowserView(mode: .search("cache"))
        .background(Theme.background)
        .environment(PreviewData.scanned())
        .preferredColorScheme(.dark)
}
#endif
