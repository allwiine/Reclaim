//
//  DevFolderPicker.swift
//  Reclaim
//
//  The folder-picking dialog shared by ProjectsView and Settings.
//

import AppKit

/// The folder-picking dialog shared by ProjectsView and Settings.
@MainActor
enum DevFolderPicker {
    static func pickFolders() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = localized("projects.addPrompt", defaultValue: "Add")
        panel.message = localized(
            "projects.addMessage",
            defaultValue: "Choose the folders where your development projects live."
        )
        return panel.runModal() == .OK ? panel.urls : []
    }
}
