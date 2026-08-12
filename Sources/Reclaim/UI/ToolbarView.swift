//
//  ToolbarView.swift
//  Reclaim
//
//  The content column's header strip: view title + subtitle on the
//  left, search / rescan / the primary Reclaim action on the right.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct ToolbarView: View {
    @Environment(AppModel.self) private var model
    let destination: Destination
    let phase: ContentPhase
    @Binding var searchText: String
    let onReclaim: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.opacity)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textLabel)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 12)

            if showsActions {
                searchField

                scanButton

                Button(reclaimLabel) {
                    onReclaim()
                }
                .buttonStyle(CompactPrimaryButtonStyle(
                    enabled: model.selectedBytes > 0 || model.hasCleanableSelection
                ))
                .disabled(!model.hasCleanableSelection)
                .help(localized("toolbar.reclaimHelp", defaultValue: "Clean the selected items"))
            } else if phase == .history || phase == .settings {
                // These screens stay on screen while a scan runs, so a
                // setting tweak or a history review can kick one off
                // without navigating back first.
                scanButton
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .frame(height: Theme.toolbarHeight)
        .background(Color.white.opacity(0.02))
        .animation(Theme.quick, value: showsActions)
    }

    // MARK: - Pieces

    /// On Overview/browser a running scan replaces the whole content
    /// area, so the disabled state only ever shows on History/Settings.
    private var scanButton: some View {
        Button {
            model.scanAll()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                Text(model.isScanning
                    ? localized("menu.scanning", defaultValue: "Scanning…")
                    : model.lastScan == nil
                        ? localized("idle.scanButton", defaultValue: "Scan this Mac")
                        : localized("action.scanAgain", defaultValue: "Scan again"))
            }
        }
        .buttonStyle(.rcSecondaryCompact)
        .disabled(model.isScanning || model.isCleaning)
        .help(localized("toolbar.scanAgainHelp", defaultValue: "Scan again"))
        // ⌘R lives on the File-menu "Scan This Mac" command —
        // registering it here as well would collide.
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: 0x8B8B92))
            TextField(localized("toolbar.searchPlaceholder", defaultValue: "Search paths"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .focused($searchFocused)
                .frame(width: 110)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: Theme.radiusChip))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusChip)
                .strokeBorder(.white.opacity(searchFocused ? 0.2 : 0.06), lineWidth: 0.5)
        }
        .animation(Theme.quick, value: searchFocused)
    }

    private var showsActions: Bool {
        phase == .overview || phase == .browser || phase == .projects
    }

    private var reclaimLabel: String {
        if model.selectedBytes > 0 {
            return localized(
                "toolbar.reclaimBytes",
                defaultValue: "Reclaim \(model.selectedBytes.formattedBytesCompact)"
            )
        }
        return model.selection.isEmpty
            ? localized("toolbar.nothingSelected", defaultValue: "Nothing selected")
            : localized("toolbar.reclaimSelection", defaultValue: "Reclaim selection")
    }

    // MARK: - Titles

    private var title: String {
        switch phase {
        case .idle: localized("app.name", defaultValue: "Reclaim")
        case .scanning: localized("title.scanning", defaultValue: "Scanning")
        case .cleaning: model.disposal == .trash
            ? localized("title.movingToTrash", defaultValue: "Moving to Trash")
            : localized("title.cleaning", defaultValue: "Cleaning")
        case .done: localized("title.finished", defaultValue: "Finished")
        case .overview: localized("sidebar.overview", defaultValue: "Overview")
        case .browser: browserTitle
        case .projects: localized("sidebar.projects", defaultValue: "Projects")
        case .history: localized("sidebar.history", defaultValue: "History")
        case .settings: localized("sidebar.settings", defaultValue: "Settings")
        }
    }

    private var browserTitle: String {
        if !searchText.isEmpty { return localized("title.search", defaultValue: "Search") }
        if case .category(let category) = destination { return category.title }
        if destination == .allFindings {
            return localized("title.allFindings", defaultValue: "All findings")
        }
        return localized("title.results", defaultValue: "Results")
    }

    private var subtitle: String {
        switch phase {
        case .idle:
            return localized("toolbar.noScanYet", defaultValue: "No scan yet")
        case .overview:
            guard let lastScan = model.lastScan else { return "" }
            let when = lastScan.formatted(.relative(presentation: .named))
            let measured = model.targets.count { model.bytes(of: $0) > 0 }
            return localized(
                "toolbar.scannedSubtitle",
                defaultValue: "Scanned \(when) · \(measured) locations"
            )
        case .browser:
            if !searchText.isEmpty { return "" }
            let targets: [CleanupTarget]
            switch destination {
            case .category(let category): targets = model.visibleTargets(in: category)
            case .allFindings: targets = model.allVisibleTargets
            default: return ""
            }
            // Before the first scan there is no size to report — a
            // formatted zero would read as a (wrong) measurement.
            guard model.lastScan != nil else {
                return localized("count.items", defaultValue: "\(targets.count) items")
            }
            let bytes = targets.reduce(Int64(0)) { $0 + model.bytes(of: $1) }
            return localized(
                "toolbar.categorySubtitle",
                defaultValue: "\(targets.count) items · \(bytes.formattedBytesCompact)"
            )
        case .history:
            let recent = model.history.count
            guard recent > 0 else { return "" }
            return localized(
                "toolbar.historySubtitle",
                defaultValue: "\(recent) cleans on record"
            )
        case .projects:
            guard model.lastScan != nil, !model.projects.isEmpty else { return "" }
            return localized(
                "toolbar.projectsSubtitle",
                defaultValue: "\(model.projects.count) projects · \(model.projectArtifactBytes.formattedBytesCompact)"
            )
        default:
            return ""
        }
    }
}

/// Toolbar-sized primary button: 26 pt, greyed when nothing is selected.
private struct CompactPrimaryButtonStyle: ButtonStyle {
    let enabled: Bool
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(enabled ? Theme.onAccent : Theme.textQuaternary)
            .padding(.horizontal, 13)
            .frame(height: 26)
            .background {
                if enabled {
                    RoundedRectangle(cornerRadius: Theme.radiusChip)
                        .fill(Theme.accentGradient)
                } else {
                    RoundedRectangle(cornerRadius: Theme.radiusChip)
                        .fill(Color.white.opacity(0.06))
                }
            }
            .shadow(color: enabled ? Theme.accent.opacity(0.35) : .clear, radius: 5, y: 2)
            .brightness(isHovered && enabled ? 0.06 : 0)
            .scaleEffect(configuration.isPressed && enabled ? 0.97 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
            .animation(Theme.quick, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Toolbar", traits: .sizeThatFitsLayout) {
    @Previewable @State var search = ""
    VStack(spacing: 0) {
        ToolbarView(
            destination: .overview,
            phase: .overview,
            searchText: $search,
            onReclaim: {}
        )
    }
    .frame(width: 1000)
    .background(Theme.background)
    .environment(PreviewData.scanned())
    .preferredColorScheme(.dark)
}
#endif
