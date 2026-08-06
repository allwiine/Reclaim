//
//  ReclaimApp.swift
//  Reclaim
//
//  App entry point. Deliberately thin: scene declarations only.
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
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 920, minHeight: 560)
        }
        .defaultSize(width: 1080, height: 700)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
