//
//  RootView.swift
//  Reclaim
//
//  The app shell: custom sidebar + content column, the flow state
//  machine (idle → scanning → dashboard/browser → cleaning → done),
//  and the confirmation overlay. All state lives in AppModel; this
//  view only routes.
//

import AppKit
import ReclaimAppCore
import ReclaimKit
import SwiftUI

/// Content destinations (the sidebar routes to all but `allFindings`,
/// which only the overview's "Review everything" button reaches).
enum Destination: Hashable {
    case overview
    case category(ToolCategory)
    case allFindings
    case projects
    case history
    case settings
}

/// The flow state currently occupying the content area.
enum ContentPhase: Equatable {
    case idle, scanning, cleaning, done, overview, browser, projects, history, settings
}

/// What a pending clean confirmation covers: everything selected, a
/// single target ("Clean just this" — the rest of the selection
/// stays), or a single project's ticked artifacts.
enum ConfirmScope: Hashable {
    case selection
    case single(CleanupTarget.ID)
    case project(DiscoveredProject.ID)
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var destination: Destination = .overview
    @State private var searchText = ""
    @State private var confirmScope: ConfirmScope?
    @State private var isShowingDone = false
    /// The specific target a tap navigated to (overview rows), so the
    /// browser anchors its inspector on that row and not the first one.
    /// Cleared by plain category/sidebar navigation.
    @State private var inspectedTargetID: CleanupTarget.ID?

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(destination: sidebarDestination)
                .frame(width: Theme.sidebarWidth)

            Rectangle()
                .fill(Theme.divider)
                .frame(width: 1)

            content
                .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundDeep)
        .overlay {
            if let scope = confirmScope {
                ConfirmSheet(
                    scope: scope,
                    onCancel: { confirmScope = nil },
                    onConfirm: {
                        confirmScope = nil
                        let cleanScope: AppModel.CleanScope = switch scope {
                        case .selection: .selection
                        case .single(let id): .targets([id])
                        case .project(let id): .projectArtifacts(id)
                        }
                        model.cleanSelected(scope: cleanScope)
                    }
                )
                .transition(.opacity)
                .zIndex(1)
                // While the sheet is up the background scan defers, so
                // it cannot clear the selection under review. Covers
                // window close too — onDisappear fires either way.
                .onAppear { model.isReviewingSelection = true }
                .onDisappear { model.isReviewingSelection = false }
            }
        }
        .animation(Theme.flow, value: confirmScope)
        .onChange(of: model.lastCleanSummary != nil) { _, hasSummary in
            // A finished pass (real or dry run) lands on the Done screen.
            if hasSummary {
                isShowingDone = true
                destination = flowDestination
            }
        }
        .onChange(of: model.isScanning) { _, isScanning in
            // A scan (manual ⌘R, menu bar) clears the selection; a
            // confirmation left open would show an empty, dead sheet.
            if isScanning { confirmScope = nil }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 1100, minHeight: 660)
        #if DEBUG
        // Smoke-test hooks: `--order-front` forces the window on screen
        // when launched from a shell (a hidden window gets no display
        // link); `--scan-on-launch` starts a scan immediately.
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--order-front") {
                // windows.first can be a MenuBarExtra status window (its
                // position in NSApp.windows varies with launch conditions,
                // e.g. an -AppleLanguages override); pick the real one.
                let main = NSApp.windows.first { $0.canBecomeMain } ?? NSApp.windows.first
                main?.orderFrontRegardless()
                NSApp.activate()
            }
            if arguments.contains("--scan-on-launch") {
                model.scanAll()
            }
            // `--open=history|settings|<category rawValue>` jumps straight
            // to a destination for screenshot-driven smoke tests.
            if let raw = arguments.first(where: { $0.hasPrefix("--open=") })?.dropFirst(7) {
                switch String(raw) {
                case "history": destination = .history
                case "settings": destination = .settings
                case "all": destination = .allFindings
                case "projects": destination = .projects
                default:
                    if let category = ToolCategory(rawValue: String(raw)) {
                        destination = .category(category)
                    }
                }
            }
        }
        #endif
    }

    /// Where the flow states render: overview/category, never settings.
    private var flowDestination: Destination {
        switch destination {
        case .history, .settings: .overview
        default: destination
        }
    }

    /// The sidebar's route: a user click also leaves the post-clean
    /// result screen, which otherwise occupies the content area for
    /// overview/category destinations until dismissed, and clears any
    /// active search — otherwise "Overview" would appear to do nothing
    /// while search results keep the content area. Only sidebar sets
    /// travel through here — the programmatic destination change when
    /// a pass finishes must not dismiss the screen it just showed.
    private var sidebarDestination: Binding<Destination> {
        Binding(
            get: { destination },
            set: { newValue in
                destination = newValue
                searchText = ""
                inspectedTargetID = nil
                if isShowingDone {
                    isShowingDone = false
                    model.lastCleanSummary = nil
                }
            }
        )
    }

    // MARK: - Content column

    private var content: some View {
        VStack(spacing: 0) {
            ToolbarView(
                destination: destination,
                phase: phase,
                searchText: $searchText,
                onReclaim: { confirmScope = .selection }
            )

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            main
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            FooterBar()
        }
        .background(Theme.background)
    }

    private var phase: ContentPhase {
        switch destination {
        case .history: return .history
        case .settings: return .settings
        case .overview, .category, .allFindings, .projects:
            if model.isCleaning { return .cleaning }
            if isShowingDone, model.lastCleanSummary != nil { return .done }
            if model.isScanning { return .scanning }
            // Categories and search are browsable before the first scan
            // too — the catalogue itself is worth exploring; only the
            // overview needs measurements and shows the hero instead.
            if !searchText.isEmpty { return .browser }
            if case .category = destination { return .browser }
            if destination == .allFindings { return .browser }
            if destination == .projects { return .projects }
            if model.lastScan == nil { return .idle }
            return .overview
        }
    }

    @ViewBuilder
    private var main: some View {
        switch phase {
        case .idle:
            IdleView()
                .transition(.opacity)
        case .scanning:
            ScanningView()
                .transition(.opacity)
        case .cleaning:
            CleaningView()
                .transition(.opacity)
        case .done:
            if let summary = model.lastCleanSummary {
                DoneView(summary: summary) {
                    isShowingDone = false
                    model.lastCleanSummary = nil
                    destination = .overview
                }
                .transition(.opacity)
            }
        case .overview:
            OverviewView(
                openCategory: { category in
                    inspectedTargetID = nil
                    destination = .category(category)
                },
                openTarget: { target in
                    inspectedTargetID = target.id
                    destination = .category(target.category)
                },
                reviewEverything: {
                    inspectedTargetID = nil
                    destination = .allFindings
                },
                reclaimSafe: {
                    model.selectAllSafe()
                    confirmScope = .selection
                },
                openProjects: {
                    inspectedTargetID = nil
                    destination = .projects
                }
            )
            .transition(.opacity)
        case .browser:
            BrowserView(
                mode: browserMode,
                initialInspectedID: inspectedTargetID,
                onCleanSingle: { confirmScope = .single($0.id) }
            )
            .transition(.opacity)
        case .projects:
            ProjectsView(onCleanProject: { confirmScope = .project($0.id) })
                .transition(.opacity)
        case .history:
            HistoryView()
                .transition(.opacity)
        case .settings:
            SettingsView()
                .transition(.opacity)
        }
    }

    private var browserMode: BrowserView.Mode {
        if !searchText.isEmpty { return .search(searchText) }
        if case .category(let category) = destination { return .category(category) }
        if destination == .allFindings { return .all }
        return .search("")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Scanned", traits: .fixedLayout(width: 1320, height: 856)) {
    RootView().environment(PreviewData.scanned())
}

#Preview("First launch", traits: .fixedLayout(width: 1320, height: 856)) {
    RootView().environment(PreviewData.idle())
}
#endif
