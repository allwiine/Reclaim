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
        VStack(spacing: Theme.Space.s0) {
            ForEach(summary.cleaned) { item in
                HStack(spacing: Theme.Space.s10) {
                    Circle()
                        .fill(item.category.color)
                        .frame(width: 7, height: 7)
                    Text(item.name)
                        .themeFont(.itemName)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 10)
                    Text(item.bytesFreed.map(\.formattedBytesCompact)
                        ?? localized("confirm.sizeUnknown", defaultValue: "size unknown"))
                        .themeFont(.body)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, Theme.Space.s14)
                .padding(.vertical, Theme.Space.s10)
                .overlay(alignment: .bottom) {
                    if item.id != summary.cleaned.last?.id {
                        Rectangle().fill(Theme.rowDivider).frame(height: 1)
                    }
                }
            }
        }
        .card(radius: Theme.radiusPanel)
        .frame(width: 560)
    }

    /// Dev-folder artifacts removed by this pass.
    var artifactsList: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            SectionLabel(localized("done.artifactsHeader", defaultValue: "Project artifacts"))
            VStack(spacing: Theme.Space.s0) {
                ForEach(summary.cleanedArtifacts) { item in
                    HStack(spacing: Theme.Space.s10) {
                        Text(item.name)
                            .themeFont(.itemName)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 10)
                        Text(item.bytesFreed.map(\.formattedBytesCompact)
                            ?? localized("confirm.sizeUnknown", defaultValue: "size unknown"))
                            .themeFont(.body)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.horizontal, Theme.Space.s14)
                    .padding(.vertical, Theme.Space.s10)
                    .overlay(alignment: .bottom) {
                        if item.id != summary.cleanedArtifacts.last?.id {
                            Rectangle().fill(Theme.rowDivider).frame(height: 1)
                        }
                    }
                }
            }
            .card(radius: Theme.radiusPanel)
        }
        .frame(width: 560)
    }
}
