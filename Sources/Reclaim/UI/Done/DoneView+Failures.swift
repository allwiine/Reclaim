//
//  DoneView+Failures.swift
//  Reclaim
//
//  The "some items could not be cleaned" card, listing the first few
//  failures plus a Full Disk Access hint when that's the likely cause.
//

import ReclaimAppCore
import SwiftUI

extension DoneView {
    var failuresCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s6) {
            Label(
                localized("done.failuresTitle", defaultValue: "Some items could not be cleaned"),
                systemImage: "exclamationmark.triangle"
            )
            .themeFont(.warningTitle)
            .foregroundStyle(Theme.cautionTitle)
            ForEach(summary.failures.prefix(4), id: \.self) { failure in
                Text(failure)
                    .themeFont(.caption)
                    .foregroundStyle(Theme.textSubtle)
                    .lineLimit(2)
            }
            if summary.failures.count > 4 {
                Text(localized(
                    "done.failuresMore",
                    defaultValue: "…and \(summary.failures.count - 4) more."
                ))
                .themeFont(.caption)
                .foregroundStyle(Theme.textTertiary)
            }
            if results.hasFullDiskAccess == false {
                Text(localized(
                    "done.fullDiskAccessHint",
                    defaultValue: "If access was denied, grant Reclaim Full Disk Access in System Settings → Privacy & Security."
                ))
                .themeFont(.caption)
                .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(Theme.Space.s12)
        .frame(width: 560, alignment: .leading)
        .background(Theme.caution.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusInset))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusInset)
                .strokeBorder(Theme.caution.opacity(0.3), lineWidth: 0.5)
        }
    }
}
