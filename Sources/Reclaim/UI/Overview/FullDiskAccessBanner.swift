//
//  FullDiskAccessBanner.swift
//  Reclaim
//
//  Full Disk Access warning, restyled for the dark shell.
//

import AppKit
import SwiftUI

/// Full Disk Access warning, restyled for the dark shell.
struct FullDiskAccessBanner: View {
    var body: some View {
        HStack(spacing: Theme.Space.s12) {
            Image(systemName: "lock.shield")
                .themeFont(.warningIcon)
                .foregroundStyle(Theme.cautionBright)
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                Text(localized("fda.title", defaultValue: "Full Disk Access is not granted"))
                    .themeFont(.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(localized(
                    "fda.body",
                    defaultValue: "Some locations cannot be measured or cleaned, so results may be incomplete."
                ))
                .themeFont(.caption)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button(localized("fda.openSettingsButton", defaultValue: "Open Privacy Settings…")) {
                NSWorkspace.shared.open(PrivacyLinks.fullDiskAccess)
            }
            .rcSecondary()
        }
        .padding(.horizontal, Theme.Space.s14)
        .padding(.vertical, Theme.Space.s10)
        .background(Theme.caution.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusInset))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusInset)
                .strokeBorder(Theme.caution.opacity(0.3), lineWidth: 0.5)
        }
    }
}
