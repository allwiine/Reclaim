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
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .scaledFont(size: 16)
                .foregroundStyle(Theme.cautionBright)
            VStack(alignment: .leading, spacing: 2) {
                Text(localized("fda.title", defaultValue: "Full Disk Access is not granted"))
                    .scaledFont(size: 13, weight: .medium)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.caution.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusInset))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusInset)
                .strokeBorder(Theme.caution.opacity(0.3), lineWidth: 0.5)
        }
    }
}
