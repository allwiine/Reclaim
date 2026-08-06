//
//  ScanningView.swift
//  Reclaim
//
//  Full-screen scan progress: spinner, the path being walked, the
//  running total, and per-category results streaming in.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct ScanningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ArcSpinner()

            Text(localized("title.scanning", defaultValue: "Scanning"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 26)

            Text(model.scanProgress?.currentPath
                ?? localized("progress.finishingUp", defaultValue: "Finishing up…"))
                .font(Theme.mono(11.5))
                .foregroundStyle(Color(hex: 0x7E7E85))
                .lineLimit(1)
                .frame(height: 16)
                .padding(.top, 8)
                .contentTransition(.opacity)
                .animation(Theme.quick, value: model.scanProgress?.currentPath)

            ProgressBar(fraction: model.scanProgress?.fraction ?? 0)
                .frame(width: 420)
                .padding(.top, 20)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.totalFoundBytes.byteParts.value)
                    .font(Theme.heroNumber(34))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(Theme.smooth, value: model.totalFoundBytes)
                Text(localized(
                    "scanning.foundSoFar",
                    defaultValue: "\(model.totalFoundBytes.byteParts.unit) found so far"
                ))
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 26)

            VStack(spacing: 2) {
                ForEach(ToolCategory.allCases) { category in
                    categoryRow(category)
                }
            }
            .frame(width: 420)
            .padding(.top, 28)

            Button(localized("scanning.stopButton", defaultValue: "Stop")) {
                model.cancelScan()
            }
            .buttonStyle(.rcSecondary)
            .padding(.top, 30)
            .help(localized(
                "scanning.stopHelp",
                defaultValue: "Keep what has been measured so far"
            ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func categoryRow(_ category: ToolCategory) -> some View {
        let targets = model.targets.filter { $0.category == category }
        let finished = targets.allSatisfy { model.status(of: $0.id) != .scanning }
        let bytes = targets.reduce(Int64(0)) { $0 + model.bytes(of: $1) }
        let anyMeasured = targets.contains { model.status(of: $0.id).bytes != nil }

        return HStack(spacing: 9) {
            Circle()
                .fill(category.color)
                .frame(width: 7, height: 7)
            Text(category.title)
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            Text(anyMeasured ? bytes.formattedBytesCompact : "—")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Color(hex: 0x8E8E95))
                .contentTransition(.numericText())
                .animation(Theme.smooth, value: bytes)
        }
        .padding(.vertical, 6)
        .opacity(finished ? 1 : 0.4)
        .animation(Theme.quick, value: finished)
    }
}

// MARK: - Previews

#if DEBUG
#Preview(traits: .fixedLayout(width: 1060, height: 810)) {
    ScanningView()
        .background(Theme.background)
        .environment(PreviewData.scanned())
        .preferredColorScheme(.dark)
}
#endif
