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

/// Sidebar destinations.
enum Destination: Hashable {
    case overview
    case category(ToolCategory)
    case history
    case settings
}

/// The flow state currently occupying the content area.
enum ContentPhase: Equatable {
    case idle, scanning, cleaning, done, overview, browser, history, settings
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var destination: Destination = .overview
    @State private var searchText = ""
    @State private var isConfirmingClean = false
    @State private var isShowingDone = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(destination: $destination)
                .frame(width: Theme.sidebarWidth)

            Rectangle()
                .fill(Theme.divider)
                .frame(width: 1)

            content
                .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundDeep)
        .overlay {
            if isConfirmingClean {
                ConfirmSheet(
                    onCancel: { isConfirmingClean = false },
                    onConfirm: {
                        isConfirmingClean = false
                        model.cleanSelected()
                    }
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(Theme.flow, value: isConfirmingClean)
        .onChange(of: model.lastCleanSummary != nil) { _, hasSummary in
            // A finished pass (real or dry run) lands on the Done screen.
            if hasSummary {
                isShowingDone = true
                destination = flowDestination
            }
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
                NSApp.windows.first?.orderFrontRegardless()
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

    // MARK: - Content column

    private var content: some View {
        VStack(spacing: 0) {
            ToolbarView(
                destination: destination,
                phase: phase,
                searchText: $searchText,
                onReclaim: { isConfirmingClean = true }
            )

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            main
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
    }

    private var phase: ContentPhase {
        switch destination {
        case .history: return .history
        case .settings: return .settings
        case .overview, .category:
            if model.isCleaning { return .cleaning }
            if isShowingDone, model.lastCleanSummary != nil { return .done }
            if model.isScanning { return .scanning }
            if model.lastScan == nil { return .idle }
            if !searchText.isEmpty { return .browser }
            if case .category = destination { return .browser }
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
                openCategory: { destination = .category($0) },
                reclaimSafe: {
                    model.selectAllSafe()
                    isConfirmingClean = true
                }
            )
            .transition(.opacity)
        case .browser:
            BrowserView(mode: browserMode)
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
