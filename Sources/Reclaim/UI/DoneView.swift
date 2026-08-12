//
//  DoneView.swift
//  Reclaim
//
//  The post-clean summary screen: how much came back, where the disk
//  stands now, what was cleaned, and any failures — plus the option
//  to empty the Trash so the space is actually released.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct DoneView: View {
    @Environment(AppModel.self) private var model
    let summary: CleanSummary
    let dismiss: () -> Void

    @State private var appeared = false
    @State private var shownBytes: Int64 = 0
    @State private var trashState: TrashButtonState = .ready
    @State private var isEmptyingTrash = false
    @State private var isConfirmingEmptyTrash = false

    private enum TrashButtonState: Equatable {
        case ready, emptied
        case failed(String)
    }

    /// A pass that removed nothing is a failure, not a success — the
    /// screen must not celebrate it with a checkmark and "0 MB".
    private var nothingCleaned: Bool {
        summary.itemsRemoved == 0 && !summary.isDryRun
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                checkmark
                headline
                if let space = model.volumeSpace {
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

    // MARK: - Pieces

    private var checkmark: some View {
        let tint = nothingCleaned ? Theme.caution : Theme.safe
        return Image(systemName: summary.isDryRun
            ? "eye"
            : (nothingCleaned ? "exclamationmark.triangle" : "checkmark"))
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(nothingCleaned ? Theme.cautionTitle : Theme.accentSoft)
            .frame(width: 58, height: 58)
            .background(tint.opacity(0.16), in: Circle())
            .overlay {
                Circle().strokeBorder(tint.opacity(0.4), lineWidth: 1)
            }
            .scaleEffect(appeared ? 1 : 0.4)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: appeared)
            .symbolEffect(.bounce, options: .nonRepeating, value: appeared)
    }

    private var headline: some View {
        VStack(spacing: 8) {
            if nothingCleaned {
                Text(localized("done.nothingCleanedTitle", defaultValue: "Nothing was cleaned"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(shownBytes.byteParts.value)
                        .font(Theme.heroNumber(44))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText(value: Double(shownBytes)))
                    Text(summary.isDryRun
                        ? localized(
                            "done.unitWouldBeReclaimed",
                            defaultValue: "\(summary.reclaimedBytes.byteParts.unit) would be reclaimed"
                        )
                        : localized(
                            "done.unitReclaimed",
                            defaultValue: "\(summary.reclaimedBytes.byteParts.unit) reclaimed"
                        ))
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text(note)
                .font(Theme.cardTitle)
                .fontWeight(.regular)
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.opacity)
                .animation(Theme.quick, value: note)
        }
        .padding(.top, 22)
        .entrance(appeared, delay: 0.1)
    }

    private var note: String {
        if summary.isDryRun {
            return localized(
                "done.noteDryRun",
                defaultValue: "Dry run — nothing was touched. Turn off Dry run in Settings to clean for real."
            )
        }
        if summary.wasStopped {
            return localized(
                "done.noteStopped",
                defaultValue: "Stopped early — not every selected item was processed."
            )
        }
        if nothingCleaned {
            return localized(
                "done.noteNothingCleaned",
                defaultValue: "No items could be removed — the failures below explain why."
            )
        }
        switch summary.disposal {
        case .trash:
            return trashState == .emptied
                ? localized(
                    "done.noteTrashEmptied",
                    defaultValue: "Trash emptied. The space is available now."
                )
                : localized(
                    "done.noteMovedToTrash",
                    defaultValue: "Moved to the Trash. Empty it to release the space for good."
                )
        case .delete:
            return localized(
                "done.noteDeleted",
                defaultValue: "Deleted permanently. The space is available now."
            )
        }
    }

    private func diskAfter(_ space: VolumeSpace) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(model.volumeDisplayName)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textLabel)
                Spacer()
                Text(localized(
                    "disk.freeOfTotal",
                    defaultValue: "\(space.availableBytes.wholeGB) free of \(space.totalBytes.wholeGB)"
                ))
                .font(Theme.caption)
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

    private var cleanedList: some View {
        VStack(spacing: 0) {
            ForEach(summary.cleaned) { item in
                HStack(spacing: 10) {
                    Circle()
                        .fill(item.category.color)
                        .frame(width: 7, height: 7)
                    Text(item.name)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 10)
                    Text(item.bytesFreed.map(\.formattedBytesCompact)
                        ?? localized("confirm.sizeUnknown", defaultValue: "size unknown"))
                        .font(.system(size: 12.5))
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
    private var artifactsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(localized("done.artifactsHeader", defaultValue: "Project artifacts"))
            VStack(spacing: 0) {
                ForEach(summary.cleanedArtifacts) { item in
                    HStack(spacing: 10) {
                        Text(item.name)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 10)
                        Text(item.bytesFreed.map(\.formattedBytesCompact)
                            ?? localized("confirm.sizeUnknown", defaultValue: "size unknown"))
                            .font(.system(size: 12.5))
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

    private var failuresCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                localized("done.failuresTitle", defaultValue: "Some items could not be cleaned"),
                systemImage: "exclamationmark.triangle"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.cautionTitle)
            ForEach(summary.failures.prefix(4), id: \.self) { failure in
                Text(failure)
                    .font(Theme.caption)
                    .foregroundStyle(Color(hex: 0xB8B8BF))
                    .lineLimit(2)
            }
            if summary.failures.count > 4 {
                Text(localized(
                    "done.failuresMore",
                    defaultValue: "…and \(summary.failures.count - 4) more."
                ))
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
            }
            if model.hasFullDiskAccess == false {
                Text(localized(
                    "done.fullDiskAccessHint",
                    defaultValue: "If access was denied, grant Reclaim Full Disk Access in System Settings → Privacy & Security."
                ))
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(12)
        .frame(width: 560, alignment: .leading)
        .background(Theme.caution.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusInset))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusInset)
                .strokeBorder(Theme.caution.opacity(0.3), lineWidth: 0.5)
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button(localized("done.backToOverview", defaultValue: "Back to overview"), action: dismiss)
                .buttonStyle(.rcSecondary)
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
                .buttonStyle(.rcPrimary)
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
                .font(Theme.caption)
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

    private func emptyTrash() {
        isEmptyingTrash = true
        Task {
            let outcome = await TrashService.emptyTrash()
            isEmptyingTrash = false
            withAnimation(Theme.quick) {
                switch outcome {
                case .emptied:
                    trashState = .emptied
                    model.markTrashEmptied()
                case .failed(let message):
                    trashState = .failed(message)
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview(traits: .fixedLayout(width: 1060, height: 810)) {
    let model = PreviewData.cleaned()
    return DoneView(summary: model.lastCleanSummary!, dismiss: {})
        .background(Theme.background)
        .environment(model)
        .preferredColorScheme(.dark)
}
#endif
