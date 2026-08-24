//
//  SettingsView.swift
//  Reclaim
//
//  In-window settings, grouped like the design: cleaning behavior,
//  scanning behavior, the menu bar summary, permissions, and the
//  structural exclusions Reclaim never touches.
//

import ReclaimAppCore
import ReclaimKit
#if canImport(Sparkle)
import Sparkle
#endif
import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) var settings
    @Environment(ProjectsModel.self) var projects
    @Environment(TargetResultsModel.self) var results

    @State var launchAtLogin = false
    @State var launchAtLoginFailed = false
    @State var notificationsDenied = false
    // Mirrors Sparkle's `automaticallyChecksForUpdates`, which is not
    // observable: binding a Toggle straight to it leaves the switch knob
    // frozen because writing it invalidates no SwiftUI state. Seeded from
    // Sparkle in `.task`, written through on toggle.
    @State private var autoUpdateChecks = true

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                #if canImport(Sparkle)
                section(localized("settings.sectionUpdates", defaultValue: "Updates")) {
                    SettingRow(
                        localized(
                            "settings.autoUpdateCheck",
                            defaultValue: "Check for updates automatically"
                        ),
                        help: localized(
                            "settings.autoUpdateCheckHelp",
                            defaultValue: "Reclaim checks for new versions in the background and offers them when they are ready."
                        ),
                        isOn: Binding(
                            get: { autoUpdateChecks },
                            set: { newValue in
                                autoUpdateChecks = newValue
                                UpdaterModel.shared.updater.automaticallyChecksForUpdates = newValue
                            }
                        )
                    )
                }
                #endif

                if LoginItemService.isAvailable {
                    section(localized("settings.sectionGeneral", defaultValue: "General")) {
                        launchAtLoginRow
                    }
                }

                section(localized("settings.sectionCleaning", defaultValue: "Cleaning")) {
                    SettingRow(
                        localized("settings.moveToTrash", defaultValue: "Move items to the Trash"),
                        help: localized(
                            "settings.moveToTrashHelp",
                            defaultValue: "The default. Nothing leaves your Mac until you empty the Trash."
                        ),
                        isOn: Binding(
                            get: { settings.disposal == .trash },
                            set: { settings.disposal = $0 ? .trash : .delete }
                        )
                    )
                    SettingRow(
                        localized("settings.dryRun", defaultValue: "Dry run"),
                        help: localized(
                            "settings.dryRunHelp",
                            defaultValue: "Report what would be removed without touching anything."
                        ),
                        isOn: $settings.dryRun
                    )
                    SettingRow(
                        localized("settings.preselectCaution", defaultValue: "Preselect Caution items"),
                        help: localized(
                            "settings.preselectCautionHelp",
                            defaultValue: "Off by default. Only Safe items are selected after a scan."
                        ),
                        isOn: $settings.preselectCaution,
                        isLast: true
                    )
                }

                section(localized("settings.sectionScanning", defaultValue: "Scanning")) {
                    SettingRow(
                        localized(
                            "settings.weeklyScan",
                            defaultValue: "Scan weekly in the background"
                        ),
                        help: localized(
                            "settings.weeklyScanHelp",
                            defaultValue: "Runs quietly while Reclaim is open, once a week has passed."
                        ),
                        isOn: $settings.weeklyScanEnabled
                    )
                    SettingRow(
                        localized(
                            "settings.notifyLarge",
                            defaultValue: "Notify when more than \(SettingsStore.notificationThresholdBytes.formattedBytesCompact) is reclaimable"
                        ),
                        help: localized(
                            "settings.notifyLargeHelp",
                            defaultValue: "A single notification after each background scan that finds that much."
                        ),
                        isOn: $settings.notifyLargeReclaimable
                    )
                    if settings.notifyLargeReclaimable, notificationsDenied {
                        notificationsDeniedRow
                    }
                    SettingRow(
                        localized(
                            "settings.showNotInstalled",
                            defaultValue: "Show tools that are not installed"
                        ),
                        help: localized(
                            "settings.showNotInstalledHelp",
                            defaultValue: "Keep catalogue entries visible even when the tool was not found on this Mac."
                        ),
                        isOn: $settings.showNotInstalled
                    )
                    SettingRow(
                        localized(
                            "settings.showEmpty",
                            defaultValue: "Show empty locations"
                        ),
                        help: localized(
                            "settings.showEmptyHelp",
                            defaultValue: "Keep locations listed even when the last scan measured nothing in them."
                        ),
                        isOn: $settings.showEmpty,
                        isLast: true
                    )
                }

                section(localized("settings.sectionDevFolders", defaultValue: "Development folders")) {
                    devFoldersRows
                }

                section(localized("settings.sectionMenuBar", defaultValue: "Menu bar")) {
                    SettingRow(
                        localized(
                            "settings.menuBarExtra",
                            defaultValue: "Show Reclaim in the menu bar"
                        ),
                        help: localized(
                            "settings.menuBarExtraHelp",
                            defaultValue: "A compact summary with quick access to scanning and safe cleanup."
                        ),
                        isOn: $settings.menuBarExtraEnabled,
                        isLast: true
                    )
                }

                permissions
                exclusions
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 26)
            .padding(.top, 24)
            .padding(.bottom, 48)
        }
        .task {
            if LoginItemService.isAvailable {
                launchAtLogin = LoginItemService.isEnabled
            }
            #if canImport(Sparkle)
            autoUpdateChecks = UpdaterModel.shared.updater.automaticallyChecksForUpdates
            #endif
            await refreshNotificationStatus()
        }
        .onChange(of: settings.notifyLargeReclaimable) { _, enabled in
            // Ask for permission the moment the user opts in — not
            // silently at the first (possibly weeks-later) notification.
            guard enabled else { return }
            Task {
                await requestNotificationAuthorization()
                await refreshNotificationStatus()
            }
        }
    }

    // MARK: - Sections

    private func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(title)
            VStack(spacing: 0, content: rows)
                .card(radius: Theme.radiusPanel)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview(traits: .fixedLayout(width: 1060, height: 810)) {
    SettingsView()
        .background(Theme.background)
        .appEnvironment(PreviewData.scanned())
        .preferredColorScheme(.dark)
}
#endif
