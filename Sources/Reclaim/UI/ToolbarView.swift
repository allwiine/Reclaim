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
    /// Kept for `hasCleanableSelection` and `selectedBytes` only —
    /// cross-model members.
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @Environment(ActivityModel.self) private var activity
    @Environment(TargetResultsModel.self) private var results
    @Environment(SelectionModel.self) private var selection
    @Environment(ProjectsModel.self) private var projects
    @Environment(ScanCoordinator.self) private var scanner
    @Environment(HistoryModel.self) private var history
    let destination: Destination
    let phase: ContentPhase
    @Binding var searchText: String
    let onReclaim: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Space.s12) {
            Text(title)
                .themeFont(.toolbarTitle)
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.opacity)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .themeFont(.meta)
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
                .rcPrimaryCompact()
                .disabled(!model.hasCleanableSelection)
                .help(localized("toolbar.reclaimHelp", defaultValue: "Clean the selected items"))
            } else if phase == .history || phase == .settings {
                // These screens stay on screen while a scan runs, so a
                // setting tweak or a history review can kick one off
                // without navigating back first.
                scanButton
            }
        }
        .padding(.leading, Theme.Space.s18)
        .padding(.trailing, Theme.Space.s14)
        .frame(height: Theme.toolbarHeight)
        .background(Theme.chromeFill)
        .animation(Theme.quick, value: showsActions)
    }

    // MARK: - Pieces

    /// On Overview/browser a running scan replaces the whole content
    /// area, so the disabled state only ever shows on History/Settings.
    private var scanButton: some View {
        Button {
            scanner.scanAll()
        } label: {
            HStack(spacing: Theme.Space.s5) {
                Image(systemName: "arrow.clockwise")
                    .themeFont(.refreshIcon)
                Text(activity.isScanning
                    ? localized("menu.scanning", defaultValue: "Scanning…")
                    : results.lastScan == nil
                        ? localized("idle.scanButton", defaultValue: "Scan this Mac")
                        : localized("action.scanAgain", defaultValue: "Scan again"))
            }
        }
        .rcSecondaryCompact()
        .disabled(activity.isScanning || activity.isCleaning)
        .help(localized("toolbar.scanAgainHelp", defaultValue: "Scan again"))
        // ⌘R lives on the File-menu "Scan This Mac" command —
        // registering it here as well would collide.
    }

    private var searchField: some View {
        HStack(spacing: Theme.Space.s6) {
            Image(systemName: "magnifyingglass")
                .themeFont(.searchIcon)
                .foregroundStyle(Theme.textSearchIcon)
            TextField(localized("toolbar.searchPlaceholder", defaultValue: "Search paths"), text: $searchText)
                .textFieldStyle(.plain)
                .themeFont(.meta)
                .foregroundStyle(Theme.textPrimary)
                .focused($searchFocused)
                .frame(width: 110)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .themeFont(.searchIcon)
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Space.s9)
        .frame(height: 26)
        .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: Theme.radiusChip))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusChip)
                .strokeBorder(
                    searchFocused ? Theme.searchFieldStrokeFocused : Theme.searchFieldStroke,
                    lineWidth: 0.5
                )
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
        return selection.ids.isEmpty
            ? localized("toolbar.nothingSelected", defaultValue: "Nothing selected")
            : localized("toolbar.reclaimSelection", defaultValue: "Reclaim selection")
    }

    // MARK: - Titles

    private var title: String {
        switch phase {
        case .idle: localized("app.name", defaultValue: "Reclaim")
        case .scanning: localized("title.scanning", defaultValue: "Scanning")
        case .cleaning: settings.disposal == .trash
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
            guard let lastScan = results.lastScan else { return "" }
            let when = lastScan.formatted(.relative(presentation: .named))
            let measured = results.targets.count { results.bytes(of: $0) > 0 }
            return localized(
                "toolbar.scannedSubtitle",
                defaultValue: "Scanned \(when) · \(measured) locations"
            )
        case .browser:
            if !searchText.isEmpty { return "" }
            let targets: [CleanupTarget]
            switch destination {
            case .category(let category): targets = results.visibleTargets(in: category)
            case .allFindings: targets = results.allVisibleTargets
            default: return ""
            }
            // Before the first scan there is no size to report — a
            // formatted zero would read as a (wrong) measurement.
            guard results.lastScan != nil else {
                return localized("count.items", defaultValue: "\(targets.count) items")
            }
            let bytes = targets.reduce(Int64(0)) { $0 + results.bytes(of: $1) }
            // "All findings" lists a dev-folder pointer row too — its
            // header must account for those bytes or the rows below
            // would sum past it.
            if destination == .allFindings, projects.projectArtifactBytes > 0 {
                let total = bytes + projects.projectArtifactBytes
                return localized(
                    "toolbar.allFindingsSubtitle",
                    defaultValue: "\(targets.count) items + \(projects.projectsWithArtifactsCount) projects · \(total.formattedBytesCompact)"
                )
            }
            return localized(
                "toolbar.categorySubtitle",
                defaultValue: "\(targets.count) items · \(bytes.formattedBytesCompact)"
            )
        case .history:
            let recent = history.entries.count
            guard recent > 0 else { return "" }
            return localized(
                "toolbar.historySubtitle",
                defaultValue: "\(recent) cleans on record"
            )
        case .projects:
            guard results.lastScan != nil, !projects.discovered.isEmpty else { return "" }
            return localized(
                "toolbar.projectsSubtitle",
                defaultValue: "\(projects.discovered.count) projects · \(projects.projectArtifactBytes.formattedBytesCompact)"
            )
        default:
            return ""
        }
    }
}


// MARK: - Previews

#if DEBUG
#Preview("Toolbar", traits: .sizeThatFitsLayout) {
    @Previewable @State var search = ""
    VStack(spacing: Theme.Space.s0) {
        ToolbarView(
            destination: .overview,
            phase: .overview,
            searchText: $search,
            onReclaim: {}
        )
    }
    .frame(width: 1000)
    .background(Theme.background)
    .appEnvironment(PreviewData.scanned())
    .preferredColorScheme(.dark)
}
#endif
