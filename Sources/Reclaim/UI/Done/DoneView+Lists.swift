//
//  DoneView+Lists.swift
//  Reclaim
//
//  What got cleaned this pass: the catalogue items, and — separately —
//  the dev-folder artifacts removed alongside them.
//

import ReclaimAppCore
import SwiftUI

extension DoneView {
    var cleanedList: some View {
        VStack(spacing: 0) {
            ForEach(summary.cleaned) { item in
                HStack(spacing: 10) {
                    Circle()
                        .fill(item.category.color)
                        .frame(width: 7, height: 7)
                    Text(item.name)
                        .scaledFont(size: 13)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 10)
                    Text(item.bytesFreed.map(\.formattedBytesCompact)
                        ?? localized("confirm.sizeUnknown", defaultValue: "size unknown"))
                        .scaledFont(size: 12.5)
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: 0x8E8E95))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    if item.id != summary.cleaned.last?.id {
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                    }
                }
            }
        }
        .card(radius: Theme.radiusPanel)
        .frame(width: 560)
    }

    /// Dev-folder artifacts removed by this pass.
    var artifactsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(localized("done.artifactsHeader", defaultValue: "Project artifacts"))
            VStack(spacing: 0) {
                ForEach(summary.cleanedArtifacts) { item in
                    HStack(spacing: 10) {
                        Text(item.name)
                            .scaledFont(size: 13)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 10)
                        Text(item.bytesFreed.map(\.formattedBytesCompact)
                            ?? localized("confirm.sizeUnknown", defaultValue: "size unknown"))
                            .scaledFont(size: 12.5)
                            .monospacedDigit()
                            .foregroundStyle(Color(hex: 0x8E8E95))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        if item.id != summary.cleanedArtifacts.last?.id {
                            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                        }
                    }
                }
            }
            .card(radius: Theme.radiusPanel)
        }
        .frame(width: 560)
    }
}
