//
//  AttentionCard.swift
//  Reclaim
//
//  A "handled by tool" callout with its terminal command, shown in the
//  overview's "Needs your attention" list.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

/// A "handled by tool" callout with its terminal command.
struct AttentionCard: View {
    @Environment(TargetResultsModel.self) private var results
    let target: CleanupTarget
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(target.name)
                        .scaledFont(size: 13, weight: .medium)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(results.bytes(of: target).formattedBytesCompact)
                        .scaledFont(size: 12.5, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
                Text(target.summary)
                    .themeFont(.footnote)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let command = target.manualCommand {
                    Text(command)
                        .font(Theme.mono())
                        .foregroundStyle(Theme.accentSoft)
                        .padding(.top, 3)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                Color.black.opacity(isHovered ? 0.32 : 0.22),
                in: RoundedRectangle(cornerRadius: Theme.radiusInset)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusInset)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusInset))
        }
        .buttonStyle(.plain)
        .animation(Theme.quick, value: isHovered)
        .onHover { isHovered = $0 }
    }
}
