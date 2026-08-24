//
//  DoneView+Buttons.swift
//  Reclaim
//
//  "Back to overview" plus the Empty Trash action and its inline error.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension DoneView {
    var buttons: some View {
        HStack(spacing: 10) {
            Button(localized("done.backToOverview", defaultValue: "Back to overview"), action: dismiss)
                .rcSecondary()
                .keyboardShortcut(.cancelAction)

            if summary.disposal == .trash, !summary.isDryRun, summary.itemsRemoved > 0 {
                Button {
                    isConfirmingEmptyTrash = true
                } label: {
                    HStack(spacing: 6) {
                        if isEmptyingTrash {
                            ProgressView().controlSize(.small)
                        }
                        Text(trashButtonTitle)
                    }
                }
                .rcPrimary()
                .disabled(isEmptyingTrash || trashState == .emptied)
            }
        }
        .overlay(alignment: .bottom) {
            if case .failed(let message) = trashState {
                VStack(spacing: 3) {
                    Text(localized(
                        "done.emptyTrashFailed",
                        defaultValue: "Couldn't empty the Trash: \(message)"
                    ))
                    .foregroundStyle(Theme.dangerWarn)
                    Text(localized(
                        "done.emptyTrashAutomationHint",
                        defaultValue: "Reclaim needs permission to control Finder — check System Settings → Privacy & Security → Automation."
                    ))
                    .foregroundStyle(Theme.textTertiary)
                }
                .themeFont(.caption)
                .fixedSize()
                .offset(y: 44)
            }
        }
    }

    private var trashButtonTitle: String {
        switch trashState {
        case .emptied: localized("done.trashEmptied", defaultValue: "Trash emptied")
        case .failed: localized("done.tryAgain", defaultValue: "Try again")
        case .ready: localized("done.emptyTrashButton", defaultValue: "Empty Trash")
        }
    }

    func emptyTrash() {
        isEmptyingTrash = true
        Task {
            let outcome = await TrashService.emptyTrash()
            isEmptyingTrash = false
            withAnimation(Theme.quick) {
                switch outcome {
                case .emptied:
                    trashState = .emptied
                    history.markTrashEmptied()
                case .failed(let message):
                    trashState = .failed(message)
                }
            }
        }
    }
}
