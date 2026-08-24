//
//  ReclaimApp.swift
//  Reclaim
//
//  App entry point: the main window (custom chrome, dark-committed),
//  the optional menu bar summary, and the Settings scene.
//

import AppKit
import os
import ReclaimAppCore
import ReclaimKit
import SwiftUI

/// Bridges the single ``AppModel`` to the app delegate, which SwiftUI
/// instantiates on its own. Weak so it never keeps the model alive past
/// the `@State` that owns it.
enum ReclaimTermination {
    static weak var model: AppModel?
}

/// Guards against quitting mid-clean. Left to itself, `NSApp.terminate`
/// (⌘Q, the menu bar's Quit, the Dock) would abandon an in-flight pass:
/// a permanent delete could be interrupted half-way and every removal
/// already made would go unrecorded. Instead we defer termination,
/// unwind the pass (the in-flight target finishes, nothing is left
/// half-cleaned), persist the history, then let the app exit.
final class ReclaimAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard let model = ReclaimTermination.model, model.activity.isCleaning else {
            return .terminateNow
        }
        Log.app.info("Deferring termination to finish the clean pass")
        Task {
            await model.prepareForTermination()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct ReclaimApp: App {
    @NSApplicationDelegateAdaptor(ReclaimAppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        // When launched via `swift run` (no app bundle), make the
        // process a regular foreground app so the window activates.
        NSApplication.shared.setActivationPolicy(.regular)
        Log.app.info("Reclaim launched")
        let model = AppModel()
        _model = State(initialValue: model)
        // Hand the delegate the one model so it can drain a clean pass
        // before the process exits.
        ReclaimTermination.model = model
        // The weekly-scan loop belongs to the app, not a window: it must
        // keep running when the main window is closed and only the menu
        // bar extra remains.
        Task { await BackgroundActivity.run(model: model) }
        #if canImport(Sparkle)
        // Start Sparkle at launch so scheduled checks run even if the
        // user never opens the menu.
        _ = UpdaterModel.shared
        #endif
    }

    var body: some Scene {
        // A single Window (not a WindowGroup): Reclaim's state is one
        // shared model, so a second main window would just mirror it.
        Window(localized("app.name", defaultValue: "Reclaim"), id: "main") {
            RootView()
                .appEnvironment(model)
        }
        .defaultSize(width: 1320, height: 856)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands { commands }

        MenuBarExtra(
            localized("app.name", defaultValue: "Reclaim"),
            systemImage: "internaldrive",
            isInserted: Binding(
                get: { model.settings.menuBarExtraEnabled },
                set: { model.settings.menuBarExtraEnabled = $0 }
            )
        ) {
            MenuBarSummary()
                .appEnvironment(model)
        }

        Settings {
            SettingsView()
                .appEnvironment(model)
                .frame(width: 700, height: 560)
                .background(Theme.background)
                .preferredColorScheme(.dark)
        }
    }

    @CommandsBuilder
    private var commands: some Commands {
        // Deliberately static: reading observable state here would
        // rebuild the main menu on every model change.
        CommandGroup(after: .newItem) {
            Button(localized("menu.scanThisMac", defaultValue: "Scan This Mac")) {
                if !model.activity.isScanning, !model.activity.isCleaning {
                    model.scanner.scanAll()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
        }

        #if canImport(Sparkle)
        // Static like the group above: no observable reads in menu builders.
        CommandGroup(after: .appInfo) {
            Button(localized("menu.checkForUpdates", defaultValue: "Check for Updates…")) {
                UpdaterModel.shared.checkForUpdates()
            }
        }
        #endif
    }
}

/// Compact menu bar summary with quick actions. Cleaning always goes
/// through the main window's confirmation — never one silent click.
private struct MenuBarSummary: View {
    /// Kept for `cleanableBytes` only — a cross-model member.
    @Environment(AppModel.self) private var model
    @Environment(TargetResultsModel.self) private var results
    @Environment(ActivityModel.self) private var activity
    @Environment(ScanCoordinator.self) private var scanner
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if results.lastScan != nil {
                // Only what Reclaim itself can clean — tool-managed
                // items (Docker, Go modules) don't count as reclaimable.
                Text(localized(
                    "menu.reclaimable",
                    defaultValue: "Reclaimable: \(model.cleanableBytes.formattedBytesCompact)"
                ))
                Text(localized(
                    "menu.safeToRemove",
                    defaultValue: "Safe to remove: \(results.safeReclaimableBytes.formattedBytesCompact)"
                ))
            } else {
                Text(localized("toolbar.noScanYet", defaultValue: "No scan yet"))
            }

            Divider()

            Button(activity.isScanning
                ? localized("menu.scanning", defaultValue: "Scanning…")
                : localized("menu.scanNow", defaultValue: "Scan Now")
            ) {
                scanner.scanAll()
            }
            .disabled(activity.isScanning || activity.isCleaning)

            Button(localized("menu.reviewInReclaim", defaultValue: "Review in Reclaim…")) {
                NSApp.activate()
                openWindow(id: "main")
            }

            Divider()

            Button(localized("menu.quit", defaultValue: "Quit Reclaim")) {
                NSApp.terminate(nil)
            }
        }
    }
}
