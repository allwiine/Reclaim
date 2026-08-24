//
//  OverviewView+Disk.swift
//  Reclaim
//
//  The overview's real-disk-usage card: free space, and the
//  developer-caches / other-used / free legend beneath the bar.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension OverviewView {
    // MARK: - Disk card

    var diskCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s0) {
            HStack {
                SectionLabel(results.volumeDisplayName)
                Spacer()
                if let space = results.volumeSpace {
                    Text(localized(
                        "disk.usedOfTotal",
                        defaultValue: "\(space.usedBytes.wholeGB) used of \(space.totalBytes.wholeGB)"
                    ))
                    .themeFont(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s6) {
                Text(freeGBNumber)
                    .font(Theme.heroNumber(30))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(Theme.smooth, value: freeGBNumber)
                Text(localized("disk.gbFree", defaultValue: "GB free"))
                    .themeFont(.cardTitle)
                    .fontWeight(.regular)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, Theme.Space.s10)

            SegmentedBar(segments: diskSegments, height: 9)
                .padding(.top, Theme.Space.s12)

            VStack(spacing: Theme.Space.s6) {
                diskLegendRow(
                    localized("disk.legendDeveloperCaches", defaultValue: "Developer caches"),
                    model.totalFoundBytes.formattedBytesCompact,
                    Theme.accent
                )
                diskLegendRow(
                    localized("disk.legendOtherUsed", defaultValue: "Other used space"),
                    otherUsedBytes.wholeGB,
                    Theme.usedTrack
                )
                diskLegendRow(
                    localized("disk.legendFree", defaultValue: "Free"),
                    (results.volumeSpace?.availableBytes ?? 0).wholeGB,
                    Theme.barTrack
                )
            }
            .padding(.top, Theme.Space.s14)
        }
        .padding(Theme.cardPadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }

    private var freeGBNumber: String {
        guard let space = results.volumeSpace else { return "—" }
        return space.availableBytes.wholeGBValue
    }

    private var otherUsedBytes: Int64 {
        guard let space = results.volumeSpace else { return 0 }
        return max(0, space.usedBytes - model.totalFoundBytes)
    }

    private var diskSegments: [MeterSegment] {
        guard let space = results.volumeSpace, space.totalBytes > 0 else { return [] }
        let total = Double(space.totalBytes)
        return [
            MeterSegment(id: "dev", fraction: Double(model.totalFoundBytes) / total, color: Theme.accent),
            MeterSegment(id: "other", fraction: Double(otherUsedBytes) / total, color: Theme.usedTrack),
        ]
    }

    private func diskLegendRow(_ name: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: Theme.Space.s8) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name)
                .themeFont(.meta)
                .foregroundStyle(Theme.textRowLabel)
            Spacer(minLength: 8)
            Text(value)
                .themeFont(.meta)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
