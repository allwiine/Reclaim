//
//  SettingsView+Exclusions.swift
//  Reclaim
//
//  The "Excluded from scans" section: every structural exclusion group
//  Reclaim's catalogue never touches, grouped and listed with its reason.
//

import ReclaimKit
import SwiftUI

extension SettingsView {
    var exclusions: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(localized("settings.sectionExclusions", defaultValue: "Excluded from scans"))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ExclusionGroup.allCases) { group in
                    exclusionGroup(group)
                }

                Text(localized(
                    "settings.exclusionsFootnote",
                    defaultValue: "Reclaim's catalogue holds only caches, logs and scratch data. Credentials, settings and other user data are excluded structurally: they are not part of the catalogue, a unit test forbids any target from touching them, and the cleanup engine refuses them at runtime."
                ))
                .themeFont(.footnote)
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

    private func exclusionGroup(_ group: ExclusionGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.displayName)
                .themeFont(.caption)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 4)
            ForEach(ExclusionRegistry.entries(in: group)) { entry in
                ForEach(entry.paths, id: \.self) { path in
                    exclusionRow(path, entry.reason)
                }
            }
        }
    }

    private func exclusionRow(_ path: String, _ reason: String) -> some View {
        HStack(spacing: 10) {
            Text(path)
                .font(Theme.mono(11.5))
                .foregroundStyle(Color(hex: 0xC8C8CF))
            Spacer(minLength: 8)
            Text(reason)
                .themeFont(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
