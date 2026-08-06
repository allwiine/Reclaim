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
                section("Cleaning") {
                    SettingRow(
                        "Move items to the Trash",
                        help: "The default. Nothing leaves your Mac until you empty the Trash.",
                        isOn: Binding(
                            get: { model.disposal == .trash },
                            set: { model.disposal = $0 ? .trash : .delete }
                        )
                    )
                    SettingRow(
                        "Dry run",
                        help: "Report what would be removed without touching anything.",
                        isOn: $model.dryRun
                    )
                    SettingRow(
                        "Preselect Caution items",
                        help: "Off by default. Only Safe items are selected after a scan.",
                        isOn: $model.preselectCaution,
                        isLast: true
                    )
                }

                section("Scanning") {
                    SettingRow(
                        "Scan weekly in the background",
                        help: "Runs quietly while Reclaim is open, once a week has passed.",
                        isOn: $model.weeklyScanEnabled
                    )
                    SettingRow(
                        "Notify when more than 25 GB is reclaimable",
                        help: "A single notification after a background scan, never repeated for the same finding.",
                        isOn: $model.notifyLargeReclaimable
                    )
                    SettingRow(
                        "Show tools that are not installed",
                        help: "Keep catalogue entries visible even when the tool was not found on this Mac.",
                        isOn: $model.showNotInstalled,
                        isLast: true
                    )
                }

                section("Menu bar") {
                    SettingRow(
                        "Show Reclaim in the menu bar",
                        help: "A compact summary with quick access to scanning and safe cleanup.",
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
            SectionLabel("Permissions")
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Full Disk Access")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Some locations (for example parts of ~/Library) may require Full Disk Access to scan or clean.")
                        .font(.system(size: 12))
                        .lineSpacing(2.5)
                        .foregroundStyle(Color(hex: 0x8E8E95))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Open Privacy Settings…") {
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
            SectionLabel("Excluded from scans")
            VStack(alignment: .leading, spacing: 8) {
                exclusionRow("~/.claude.json", "auth — never in catalogue")
                exclusionRow("~/.claude/settings.json", "never in catalogue")
                exclusionRow("~/.claude/plugins", "never in catalogue")
                exclusionRow("~/Library/Keychains", "never in catalogue")

                Text("Reclaim's catalogue holds only caches, logs and scratch data. Credentials, settings and plugins are excluded structurally — they are not part of the catalogue and cannot be selected.")
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
