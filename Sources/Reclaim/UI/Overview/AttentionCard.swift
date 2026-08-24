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
            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s10) {
                    Text(target.name)
                        .themeFont(.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(results.bytes(of: target).formattedBytesCompact)
                        .themeFont(.amount)
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
                        .padding(.top, Theme.Space.s3)
                }
            }
            .padding(.horizontal, Theme.Space.s12)
            .padding(.vertical, Theme.Space.s11)
            .background(
                isHovered ? Theme.calloutFillHovered : Theme.calloutFill,
                in: RoundedRectangle(cornerRadius: Theme.radiusInset)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusInset)
                    .strokeBorder(Theme.calloutStroke, lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusInset))
        }
        .buttonStyle(.plain)
        .animation(Theme.quick, value: isHovered)
        .onHover { isHovered = $0 }
    }
}
