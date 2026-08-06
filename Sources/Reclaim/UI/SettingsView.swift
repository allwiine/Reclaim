//
//  SettingsView.swift
//  Reclaim
//
//  In-window settings, grouped like the design: cleaning behavior,
//  scanning behavior, the menu bar summary, permissions, and the
//  structural exclusions Reclaim never touches.
//

import AppKit
import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                section(localized("settings.sectionCleaning", defaultValue: "Cleaning")) {
                    SettingRow(
                        localized("settings.moveToTrash", defaultValue: "Move items to the Trash"),
                        help: localized(
                            "settings.moveToTrashHelp",
                            defaultValue: "The default. Nothing leaves your Mac until you empty the Trash."
                        ),
                        isOn: Binding(
                            get: { model.disposal == .trash },
                            set: { model.disposal = $0 ? .trash : .delete }
                        )
                    )
                    SettingRow(
                        localized("settings.dryRun", defaultValue: "Dry run"),
                        help: localized(
                            "settings.dryRunHelp",
                            defaultValue: "Report what would be removed without touching anything."
                        ),
                        isOn: $model.dryRun
                    )
                    SettingRow(
                        localized("settings.preselectCaution", defaultValue: "Preselect Caution items"),
                        help: localized(
                            "settings.preselectCautionHelp",
                            defaultValue: "Off by default. Only Safe items are selected after a scan."
                        ),
                        isOn: $model.preselectCaution,
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
                        isOn: $model.weeklyScanEnabled
                    )
                    SettingRow(
                        localized(
                            "settings.notifyLarge",
                            defaultValue: "Notify when more than \(AppModel.notificationThresholdBytes.formattedBytesCompact) is reclaimable"
                        ),
                        help: localized(
                            "settings.notifyLargeHelp",
                            defaultValue: "A single notification after each background scan that finds that much."
                        ),
                        isOn: $model.notifyLargeReclaimable
                    )
                    SettingRow(
                        localized(
                            "settings.showNotInstalled",
                            defaultValue: "Show tools that are not installed"
                        ),
                        help: localized(
                            "settings.showNotInstalledHelp",
                            defaultValue: "Keep catalogue entries visible even when the tool was not found on this Mac."
                        ),
                        isOn: $model.showNotInstalled,
                        isLast: true
                    )
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
                        isOn: $model.menuBarExtraEnabled,
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
    }

    // MARK: - Sections

    private func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(title)
            VStack(spacing: 0, content: rows)
                .card(radius: Theme.radiusPanel)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(localized("settings.sectionPermissions", defaultValue: "Permissions"))
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("settings.fullDiskAccess", defaultValue: "Full Disk Access"))
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(localized(
                        "settings.fullDiskAccessHelp",
                        defaultValue: "Some locations (for example parts of ~/Library) may require Full Disk Access to scan or clean."
                    ))
                    .font(.system(size: 12))
                    .lineSpacing(2.5)
                    .foregroundStyle(Color(hex: 0x8E8E95))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(localized("fda.openSettingsButton", defaultValue: "Open Privacy Settings…")) {
                    NSWorkspace.shared.open(PrivacyLinks.fullDiskAccess)
                }
                .buttonStyle(.rcSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .card(radius: Theme.radiusPanel)
        }
    }

    private var exclusions: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(localized("settings.sectionExclusions", defaultValue: "Excluded from scans"))
            VStack(alignment: .leading, spacing: 8) {
                exclusionRow(
                    "~/.claude.json",
                    localized("settings.exclusionAuth", defaultValue: "auth — never in catalogue")
                )
                exclusionRow(
                    "~/.claude/settings.json",
                    localized("settings.exclusionNever", defaultValue: "never in catalogue")
                )
                exclusionRow(
                    "~/.claude/plugins",
                    localized("settings.exclusionNever", defaultValue: "never in catalogue")
                )
                exclusionRow(
                    "~/Library/Keychains",
                    localized("settings.exclusionNever", defaultValue: "never in catalogue")
                )
                exclusionRow(
                    "~/.aspnet",
                    localized("settings.exclusionCerts", defaultValue: "dev certs & keys — never in catalogue")
                )
                exclusionRow(
                    "~/.dotnet/tools",
                    localized("settings.exclusionTools", defaultValue: "installed tools — never in catalogue")
                )

                Text(localized(
                    "settings.exclusionsFootnote",
                    defaultValue: "Reclaim's catalogue holds only caches, logs and scratch data. Credentials, settings and plugins are excluded structurally — they are not part of the catalogue and cannot be selected."
                ))
                .font(Theme.footnote)
                .lineSpacing(2.5)
                .foregroundStyle(Theme.textQuaternary)
                .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(radius: Theme.radiusPanel)
        }
    }

    private func exclusionRow(_ path: String, _ reason: String) -> some View {
        HStack(spacing: 10) {
            Text(path)
                .font(Theme.mono(11.5))
                .foregroundStyle(Color(hex: 0xC8C8CF))
            Spacer(minLength: 8)
            Text(reason)
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

// MARK: - Row

/// One switch row inside a settings card.
private struct SettingRow: View {
    let title: String
    let help: String
    @Binding var isOn: Bool
    var isLast: Bool

    init(_ title: String, help: String, isOn: Binding<Bool>, isLast: Bool = false) {
        self.title = title
        self.help = help
        self._isOn = isOn
        self.isLast = isLast
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(help)
                    .font(.system(size: 12))
                    .lineSpacing(2.5)
                    .foregroundStyle(Color(hex: 0x8E8E95))
            }
        }
        .toggleStyle(.rcSwitch)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Theme.separator).frame(height: 1)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview(traits: .fixedLayout(width: 1060, height: 810)) {
    SettingsView()
        .background(Theme.background)
        .environment(PreviewData.scanned())
        .preferredColorScheme(.dark)
}
#endif
