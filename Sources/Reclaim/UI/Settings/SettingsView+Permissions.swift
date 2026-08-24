//
//  SettingsView+Permissions.swift
//  Reclaim
//
//  The Permissions section: Full Disk Access status and the button to
//  open its Privacy Settings pane.
//

import AppKit
import ReclaimAppCore
import SwiftUI

extension SettingsView {
    var permissions: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s9) {
            SectionLabel(localized("settings.sectionPermissions", defaultValue: "Permissions"))
            HStack(spacing: Theme.Space.s16) {
                VStack(alignment: .leading, spacing: Theme.Space.s3) {
                    Text(localized("settings.fullDiskAccess", defaultValue: "Full Disk Access"))
                        .themeFont(.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(localized(
                        "settings.fullDiskAccessHelp",
                        defaultValue: "Some locations (for example parts of ~/Library) may require Full Disk Access to scan or clean."
                    ))
                    .themeFont(.meta)
                    .lineSpacing(2.5)
                    .foregroundStyle(Theme.textTertiary)
                    HStack(spacing: Theme.Space.s6) {
                        Circle()
                            .fill(fdaStatusColor)
                            .frame(width: 7, height: 7)
                        Text(fdaStatusText)
                            .themeFont(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.top, Theme.Space.s4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(localized("fda.openSettingsButton", defaultValue: "Open Privacy Settings…")) {
                    NSWorkspace.shared.open(PrivacyLinks.fullDiskAccess)
                }
                .rcSecondary()
            }
            .padding(.horizontal, Theme.Space.s16)
            .padding(.vertical, Theme.Space.s13)
            .card(radius: Theme.radiusPanel)
        }
    }

    private var fdaStatusText: String {
        switch results.hasFullDiskAccess {
        case .some(true):
            localized("settings.fdaStatusGranted", defaultValue: "Granted")
        case .some(false):
            localized("settings.fdaStatusDenied", defaultValue: "Not granted")
        case .none:
            localized("settings.fdaStatusUnknown", defaultValue: "Checked when a scan runs")
        }
    }

    private var fdaStatusColor: Color {
        switch results.hasFullDiskAccess {
        case .some(true): Theme.safe
        case .some(false): Theme.dangerWarn
        case .none: Theme.textQuaternary
        }
    }
}
