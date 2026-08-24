//
//  CleaningView.swift
//  Reclaim
//
//  Full-screen clean progress: which location is being disposed of,
//  how far along the pass is, and a way to stop safely.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct CleaningView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ActivityModel.self) private var activity
    @Environment(CleanCoordinator.self) private var cleaner

    var body: some View {
        VStack(spacing: Theme.Space.s0) {
            Text(settings.disposal == .trash
                ? localized("title.movingToTrash", defaultValue: "Moving to Trash")
                : localized("title.deleting", defaultValue: "Deleting"))
                .themeFont(.phaseHeadline)
                .foregroundStyle(Theme.textPrimary)

            Text(activity.cleanProgress?.targetPath
                ?? activity.cleanProgress?.targetName
                ?? localized("progress.finishingUp", defaultValue: "Finishing up…"))
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.textProgressPath)
                .lineLimit(1)
                .frame(height: 16)
                .padding(.top, Theme.Space.s10)
                .contentTransition(.opacity)
                .animation(Theme.quick, value: activity.cleanProgress?.targetPath)

            ProgressBar(fraction: activity.cleanProgress?.fraction ?? 0, height: 6)
                .frame(width: 420)
                .padding(.top, Theme.Space.s20)

            if let progress = activity.cleanProgress {
                Text(localized(
                    "cleaning.progress",
                    defaultValue: "\(progress.index) of \(progress.total) locations"
                ))
                .themeFont(.body)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, Theme.Space.s14)
                .contentTransition(.numericText())
                .animation(Theme.smooth, value: progress.index)
            }

            Button(activity.isCancellingClean
                ? localized("cleaning.stoppingButton", defaultValue: "Stopping after this item…")
                : localized("cleaning.stopButton", defaultValue: "Stop after this item")
            ) {
                cleaner.cancelClean()
            }
            .rcSecondary()
            .disabled(activity.isCancellingClean)
            .padding(.top, Theme.Space.s30)
            .help(localized(
                "cleaning.stopHelp",
                defaultValue: "The item being cleaned finishes; the rest are skipped"
            ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.s40)
    }
}

// MARK: - Previews

#if DEBUG
#Preview(traits: .fixedLayout(width: 1060, height: 810)) {
    CleaningView()
        .background(Theme.background)
        .appEnvironment(PreviewData.scanned())
        .preferredColorScheme(.dark)
}
#endif
