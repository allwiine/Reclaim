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

@main
struct ReclaimApp: App {
    @State private var model = AppModel()

    init() {
        // When launched via `swift run` (no app bundle), make the
        // process a regular foreground app so the window activates.
        NSApplication.shared.setActivationPolicy(.regular)
        Log.app.info("Reclaim launched")
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(model)
                .task {
                    await BackgroundActivity.run(model: model)
                }
        }
        .defaultSize(width: 1320, height: 856)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands { commands }

        MenuBarExtra(
            localized("app.name", defaultValue: "Reclaim"),
            systemImage: "internaldrive",
            isInserted: Binding(
                get: { model.menuBarExtraEnabled },
                set: { model.menuBarExtraEnabled = $0 }
            )
        ) {
            MenuBarSummary()
                .environment(model)
        }

        Settings {
            SettingsView()
                .environment(model)
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
                if !model.isScanning, !model.isCleaning {
                    model.scanAll()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}

/// Compact menu bar summary with quick actions. Cleaning always goes
/// through the main window's confirmation — never one silent click.
private struct MenuBarSummary: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if model.lastScan != nil {
                Text(localized(
                    "menu.reclaimable",
                    defaultValue: "Reclaimable: \(model.totalFoundBytes.formattedBytesCompact)"
                ))
                Text(localized(
                    "menu.safeToRemove",
                    defaultValue: "Safe to remove: \(model.safeReclaimableBytes.formattedBytesCompact)"
                ))
            } else {
                Text(localized("toolbar.noScanYet", defaultValue: "No scan yet"))
            }

            Divider()

            Button(model.isScanning
                ? localized("menu.scanning", defaultValue: "Scanning…")
                : localized("menu.scanNow", defaultValue: "Scan Now")
            ) {
                model.scanAll()
            }
            .disabled(model.isScanning || model.isCleaning)

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
