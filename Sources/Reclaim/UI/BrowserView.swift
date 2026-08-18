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
        /// Every visible target across categories ("Review everything").
        case all
        case search(String)
    }

    @Environment(AppModel.self) private var model
    let mode: Mode
    /// Row to anchor the inspector on when arriving from a tap on a
    /// specific target elsewhere (overview lists); `nil` falls back to
    /// the first row.
    var initialInspectedID: CleanupTarget.ID?
    /// Opens the single-target clean confirmation ("Clean just this").
    var onCleanSingle: (CleanupTarget) -> Void = { _ in }
    /// Routes to the Projects screen ("Review everything" covers
    /// dev-folder artifacts through a pointer row, not inline rows).
    var onOpenProjects: () -> Void = {}

    @State private var inspectedID: CleanupTarget.ID?

    var body: some View {
        let targets = visibleTargets

        HStack(spacing: 0) {
            VStack(spacing: 0) {
                selectionStrip

                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)

                if targets.isEmpty && !showsProjectsRow {
                    emptyState
                } else {
                    list(targets)
                }
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Theme.divider)
                .frame(width: 1)

            InspectorPanel(target: inspectedTarget(in: targets), onCleanSingle: onCleanSingle)
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
        case .all:
            return model.allVisibleTargets
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

    /// "Review everything" would under-account the headline it sits
    /// beneath without the projects' bytes — they get a pointer row.
    private var showsProjectsRow: Bool {
        mode == .all && model.projectArtifactBytes > 0
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
                .scaledFont(size: 12)
                .monospacedDigit()
                .foregroundStyle(Theme.textLabel)
                .contentTransition(.numericText())
                .animation(Theme.smooth, value: model.selection.count)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    /// Scoped to the list it sits above: counting selections the user
    /// cannot see here reads as a lie ("4 selected" over an unticked
    /// list). The global size lives on the toolbar's Reclaim button.
    private var selectionSummary: String {
        let visible = visibleTargets
        let pickedHere = visible.count { model.isSelected($0) }
        guard pickedHere > 0 else {
            return localized("browser.noItemsSelected", defaultValue: "No items selected")
        }
        let selectable = model.selectableItemCount(among: visible)
        let bytes = visible.reduce(Int64(0)) { $0 + model.selectedBytes(of: $1) }
        return localized(
            "browser.selectionSummary",
            defaultValue: "\(pickedHere) of \(selectable) items selected · \(bytes.formattedBytesCompact)"
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
                    if showsProjectsRow {
                        ProjectsLinkRow(
                            count: model.projectsWithArtifactsCount,
                            bytes: model.projectArtifactBytes,
                            open: onOpenProjects
                        )
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
                .scaledFont(size: 28)
                .foregroundStyle(Theme.textQuaternary)
            Text(emptyTitle)
                .scaledFont(size: 14, weight: .medium)
                .foregroundStyle(Theme.textSecondary)
            Text(emptyDetail)
                .themeFont(.body)
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
        case .category, .all:
            localized(
                "browser.emptyCategoryDetail",
                defaultValue: "Nothing here right now — these tools are either not installed or have nothing to clean. Settings can keep such entries visible."
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
        guard let counts = model.partialSelectionCounts(of: target) else { return nil }
        let scope = localized(
            "format.itemsOf",
            defaultValue: "\(counts.selected) of \(counts.total) items"
        )
        let size = model.selectedBytes(of: target).formattedBytesCompact
        return localized("browser.partialNote", defaultValue: "\(scope) · \(size)")
    }

    private var checkbox: some View {
        Toggle(
            localized("browser.selectAccessibility", defaultValue: "Select \(target.name)"),
            isOn: Binding(
                get: { model.isSelected(target) },
                set: { model.setSelected(target, $0) }
            )
        )
        .toggleStyle(CheckboxToggleStyle(mixed: model.isPartiallySelected(target)))
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
                    get: { model.isExcludedFromAutoSelect(target) },
                    set: { model.setExcludedFromAutoSelect(target, $0) }
                )
            )
        }
    }
}

/// The dev-folder pointer at the end of "Review everything": projects
/// are part of the totals above, but their artifacts are reviewed and
/// cleaned on the Projects screen, so this row routes there instead of
/// offering a checkbox.
private struct ProjectsLinkRow: View {
    let count: Int
    let bytes: Int64
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "folder.badge.gearshape")
                    .scaledFont(size: 10.5, weight: .medium)
                    .foregroundStyle(Color(hex: 0xB8B8BF))
                    .frame(width: 22, height: 22)
                    .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("sidebar.projects", defaultValue: "Projects"))
                        .scaledFont(size: 13.5, weight: .medium)
                        .foregroundStyle(Theme.textPrimary)
                    Text(localized(
                        "browser.projectsRowSubtitle",
                        defaultValue: "Reviewed and cleaned on the Projects screen"
                    ))
                    .themeFont(.caption)
                    .foregroundStyle(Theme.textTertiary)
                }

                Spacer(minLength: 10)

                Text(localized(
                    "toolbar.projectsSubtitle",
                    defaultValue: "\(count) projects · \(bytes.formattedBytesCompact)"
                ))
                .scaledFont(size: 13, weight: .medium)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)

                Image(systemName: "chevron.right")
                    .scaledFont(size: 10, weight: .semibold)
                    .foregroundStyle(Theme.textQuaternary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusInset))
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: Theme.radiusInset, color: Color.white.opacity(0.055))
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
