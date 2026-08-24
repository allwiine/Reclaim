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
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Text(model.settings.disposal == .trash
                ? localized("title.movingToTrash", defaultValue: "Moving to Trash")
                : localized("title.deleting", defaultValue: "Deleting"))
                .scaledFont(size: 20, weight: .semibold)
                .foregroundStyle(Theme.textPrimary)

            Text(model.activity.cleanProgress?.targetPath
                ?? model.activity.cleanProgress?.targetName
                ?? localized("progress.finishingUp", defaultValue: "Finishing up…"))
                .font(Theme.mono(11.5))
                .foregroundStyle(Color(hex: 0x7E7E85))
                .lineLimit(1)
                .frame(height: 16)
                .padding(.top, 10)
                .contentTransition(.opacity)
                .animation(Theme.quick, value: model.activity.cleanProgress?.targetPath)

            ProgressBar(fraction: model.activity.cleanProgress?.fraction ?? 0, height: 6)
                .frame(width: 420)
                .padding(.top, 20)

            if let progress = model.activity.cleanProgress {
                Text(localized(
                    "cleaning.progress",
                    defaultValue: "\(progress.index) of \(progress.total) locations"
                ))
                .scaledFont(size: 12.5)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 14)
                .contentTransition(.numericText())
                .animation(Theme.smooth, value: progress.index)
            }

            Button(model.activity.isCancellingClean
                ? localized("cleaning.stoppingButton", defaultValue: "Stopping after this item…")
                : localized("cleaning.stopButton", defaultValue: "Stop after this item")
            ) {
                model.cleaner.cancelClean()
            }
            .rcSecondary()
            .disabled(model.activity.isCancellingClean)
            .padding(.top, 30)
            .help(localized(
                "cleaning.stopHelp",
                defaultValue: "The item being cleaned finishes; the rest are skipped"
            ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
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
