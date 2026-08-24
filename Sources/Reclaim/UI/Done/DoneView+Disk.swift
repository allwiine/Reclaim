//
//  DoneView+Disk.swift
//  Reclaim
//
//  The volume's free-of-total meter, shown once a scan has measured it.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension DoneView {
    func diskAfter(_ space: VolumeSpace) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(results.volumeDisplayName)
                    .themeFont(.caption)
                    .foregroundStyle(Theme.textLabel)
                Spacer()
                Text(localized(
                    "disk.freeOfTotal",
                    defaultValue: "\(space.availableBytes.wholeGB) free of \(space.totalBytes.wholeGB)"
                ))
                .themeFont(.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.textLabel)
            }
            SegmentedBar(segments: [
                MeterSegment(
                    id: "used",
                    fraction: Double(space.usedBytes) / Double(max(1, space.totalBytes)),
                    color: .white.opacity(0.28)
                ),
            ], height: 8)
        }
        .frame(width: 560)
    }
}
