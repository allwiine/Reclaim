//
//  SettingsView+General.swift
//  Reclaim
//
//  The General section's launch-at-login row, the development-folders
//  roots list, and the notifications-denied hint shown under Scanning.
//

import AppKit
import ReclaimAppCore
import SwiftUI

extension SettingsView {
    // MARK: - Sections

    /// Login-item state lives in SMAppService, not UserDefaults — the
    /// toggle reads and writes the service directly.
    @ViewBuilder
    var launchAtLoginRow: some View {
        SettingRow(
            localized("settings.launchAtLogin", defaultValue: "Open Reclaim at login"),
            help: localized(
                "settings.launchAtLoginHelp",
                defaultValue: "Keeps the menu bar summary and weekly background scans running without opening the app yourself."
            ),
            isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    do {
                        try LoginItemService.setEnabled(newValue)
                        launchAtLogin = newValue
                        launchAtLoginFailed = false
                    } catch {
                        launchAtLoginFailed = true
                    }
                }
            ),
            isLast: !launchAtLoginFailed
        )
        if launchAtLoginFailed {
            Text(localized(
                "settings.launchAtLoginFailed",
                defaultValue: "Couldn't change the login item — manage it under System Settings → General → Login Items."
            ))
            .themeFont(.caption)
            .foregroundStyle(Theme.dangerWarn)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The dev-folder feature's configuration: the roots Reclaim
    /// searches for projects. Empty list = feature entirely inert.
    @ViewBuilder
    var devFoldersRows: some View {
        ForEach(model.projects.devRoots, id: \.path) { root in
            HStack(spacing: 10) {
                Text((root.path as NSString).abbreviatingWithTildeInPath)
                    .font(Theme.mono(11.5))
                    .foregroundStyle(Color(hex: 0xC8C8CF))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(localized("settings.removeDevFolder", defaultValue: "Remove")) {
                    model.projects.removeDevRoot(root)
                }
                .rcSecondary()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.separator).frame(height: 1)
            }
        }
        HStack {
            Text(localized(
                "settings.devFoldersHelp",
                defaultValue: "Reclaim looks for projects and regenerable artifacts (node_modules, build folders, virtualenvs) only inside these folders."
            ))
            .scaledFont(size: 12)
            .lineSpacing(2.5)
            .foregroundStyle(Color(hex: 0x8E8E95))
            Spacer(minLength: 8)
            Button(localized("settings.addDevFolder", defaultValue: "Add folder…")) {
                for url in DevFolderPicker.pickFolders() {
                    model.projects.addDevRoot(url)
                }
            }
            .rcSecondary()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    /// Shown when the notify toggle is on but macOS blocks the alert —
    /// without this the setting silently does nothing forever.
    var notificationsDeniedRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.slash")
                .scaledFont(size: 12)
                .foregroundStyle(Theme.cautionTitle)
            Text(localized(
                "settings.notificationsDenied",
                defaultValue: "Notifications for Reclaim are turned off in System Settings, so this alert cannot appear."
            ))
            .themeFont(.caption)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(localized("settings.openNotificationSettings", defaultValue: "Open Notification Settings…")) {
                NSWorkspace.shared.open(PrivacyLinks.notifications)
            }
            .rcSecondary()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
    }
}
