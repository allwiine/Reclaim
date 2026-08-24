//
//  DoneView.swift
//  Reclaim
//
//  The post-clean summary screen: how much came back, where the disk
//  stands now, what was cleaned, and any failures — plus the option
//  to empty the Trash so the space is actually released.
//

import ReclaimAppCore
import SwiftUI

struct DoneView: View {
    @Environment(AppModel.self) var model
    let summary: CleanSummary
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var appeared = false
    @State var shownBytes: Int64 = 0
    @State var trashState: TrashButtonState = .ready
    @State var isEmptyingTrash = false
    @State var isConfirmingEmptyTrash = false

    enum TrashButtonState: Equatable {
        case ready, emptied
        case failed(String)
    }

    /// A pass that removed nothing is a failure, not a success — the
    /// screen must not celebrate it with a checkmark and "0 MB".
    var nothingCleaned: Bool {
        summary.itemsRemoved == 0 && !summary.isDryRun
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                checkmark
                headline
                if let space = model.results.volumeSpace {
                    diskAfter(space)
                        .padding(.top, 36)
                        .entrance(appeared, delay: 0.25)
                }
                if !summary.cleaned.isEmpty {
                    cleanedList
                        .padding(.top, 30)
                        .entrance(appeared, delay: 0.32)
                }
                if !summary.cleanedArtifacts.isEmpty {
                    artifactsList
                        .padding(.top, summary.cleaned.isEmpty ? 30 : 10)
                        .entrance(appeared, delay: 0.34)
                }
                if !summary.failures.isEmpty {
                    failuresCard
                        .padding(.top, 14)
                        .entrance(appeared, delay: 0.36)
                }
                buttons
                    .padding(.top, 26)
                    .entrance(appeared, delay: 0.4)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 64)
            .padding(.bottom, 40)
            .padding(.horizontal, 60)
        }
        .onAppear {
            withAnimation(Theme.springy) { appeared = true }
            withAnimation(.smooth(duration: 1.0).delay(0.25)) {
                shownBytes = summary.reclaimedBytes
            }
        }
        .confirmationDialog(
            localized("done.emptyTrashTitle", defaultValue: "Empty the Trash?"),
            isPresented: $isConfirmingEmptyTrash,
            titleVisibility: .visible
        ) {
            Button(
                localized("done.emptyTrashButton", defaultValue: "Empty Trash"),
                role: .destructive
            ) {
                emptyTrash()
            }
        } message: {
            Text(localized(
                "done.emptyTrashMessage",
                defaultValue: "This empties everything in the Trash — including items Reclaim didn't put there. This cannot be undone."
            ))
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview(traits: .fixedLayout(width: 1060, height: 810)) {
    let model = PreviewData.cleaned()
    return DoneView(summary: model.activity.lastCleanSummary!, dismiss: {})
        .background(Theme.background)
        .appEnvironment(model)
        .preferredColorScheme(.dark)
}
#endif
