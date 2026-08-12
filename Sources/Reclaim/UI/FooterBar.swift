//
//  FooterBar.swift
//  Reclaim
//
//  The slim status strip under the content column: lifetime reclaimed
//  space, the last clean, and the next background scan. These are
//  app-global facts, so they live here — visible in every phase —
//  rather than as cards on the overview. The longer detail each stat
//  used to carry is available on hover.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct FooterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            item(
                label: localized("overview.reclaimedAllTime", defaultValue: "Reclaimed all time"),
                value: model.reclaimedAllTimeBytes > 0
                    ? model.reclaimedAllTimeBytes.formattedBytesCompact : "—",
                help: model.history.isEmpty
                    ? localized("overview.noCleansYet", defaultValue: "no cleans recorded yet")
                    : localized("overview.acrossCleans", defaultValue: "across \(model.history.count) cleans")
            )
            Spacer(minLength: 16)
            item(
                label: localized("overview.lastClean", defaultValue: "Last clean"),
                value: lastCleanValue,
                help: lastCleanHelp
            )
            Spacer(minLength: 16)
            item(
                label: localized("overview.nextBackgroundScan", defaultValue: "Next background scan"),
                value: nextScanValue,
                help: model.weeklyScanEnabled
                    ? localized("overview.weeklyWhileRunning", defaultValue: "weekly, while Reclaim is running")
                    : localized("overview.backgroundScansOff", defaultValue: "background scans are off")
            )
        }
        .padding(.horizontal, 18)
        .frame(height: 30)
        .background(Color.white.opacity(0.02))
    }

    private func item(label: String, value: String, help: String) -> some View {
        HStack(spacing: 7) {
            Text(label)
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.numericText())
                .animation(Theme.smooth, value: value)
        }
        .help(help)
    }

    private var lastCleanValue: String {
        guard let last = model.history.first else { return "—" }
        return last.date.formatted(date: .abbreviated, time: .omitted)
    }

    private var lastCleanHelp: String {
        guard let last = model.history.first else {
            return localized("overview.nothingCleanedYet", defaultValue: "nothing cleaned yet")
        }
        let freed = last.reclaimedBytes.formattedBytesCompact
        let when = last.date.formatted(.relative(presentation: .named))
        return localized("overview.lastCleanSub", defaultValue: "\(freed) freed · \(when)")
    }

    private var nextScanValue: String {
        guard model.weeklyScanEnabled else {
            return localized("overview.off", defaultValue: "Off")
        }
        guard let next = model.nextBackgroundScanDate else {
            return localized("overview.afterFirstScan", defaultValue: "After first scan")
        }
        return next.formatted(.dateTime.weekday(.wide).hour().minute())
    }
}

// MARK: - Previews

#if DEBUG
#Preview(traits: .sizeThatFitsLayout) {
    FooterBar()
        .frame(width: 1000)
        .background(Theme.background)
        .environment(PreviewData.scanned())
        .preferredColorScheme(.dark)
}
#endif
