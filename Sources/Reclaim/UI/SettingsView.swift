//
//  SettingsView.swift
//  Reclaim
//
//  App settings: disposal method, list filtering, and a shortcut to
//  the Full Disk Access privacy pane.
//

import AppKit
import ReclaimKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    /// Deep link to System Settings → Privacy & Security → Full Disk Access.
    private static let fullDiskAccessURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    var body: some View {
        @Bindable var model = model

        Form {
            Section("Cleaning") {
                Picker("When cleaning items", selection: $model.disposal) {
                    Text("Move to Trash (recommended)").tag(Disposal.trash)
                    Text("Delete immediately").tag(Disposal.delete)
                }
                .pickerStyle(.radioGroup)

                Text("Moving to the Trash lets you undo mistakes — space is freed once you empty the Trash.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("List") {
                Toggle("Show tools that are not installed", isOn: $model.showNotInstalled)
            }

            Section("Permissions") {
                Text("Some locations (for example parts of ~/Library) may require Full Disk Access to scan or clean.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Privacy Settings…") {
                    NSWorkspace.shared.open(Self.fullDiskAccessURL)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
