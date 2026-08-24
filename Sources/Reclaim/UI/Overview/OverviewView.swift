//
//  OverviewView.swift
//  Reclaim
//
//  The post-scan dashboard: the reclaimable ring, real disk usage,
//  category cards, the biggest single locations, tool-managed items
//  that need the user's attention, and lifetime statistics.
//

import AppKit
import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct OverviewView: View {
    /// Kept for `totalFoundBytes` and `largestFindings(limit:)` only —
    /// cross-model members.
    @Environment(AppModel.self) var model
    @Environment(TargetResultsModel.self) var results
    @Environment(ProjectsModel.self) var projects
    @Environment(ScanCoordinator.self) var scanner

    /// Jumps to a category browser.
    let openCategory: (ToolCategory) -> Void
    /// Jumps to a specific target's row in its category browser.
    let openTarget: (CleanupTarget) -> Void
    /// Opens the cross-category "all findings" browser.
    let reviewEverything: () -> Void
    /// Selects everything safe and opens the confirmation.
    let reclaimSafe: () -> Void
    /// Opens the dev-folder Projects screen.
    let openProjects: () -> Void

    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.cardGap) {
                if results.hasFullDiskAccess == false {
                    FullDiskAccessBanner()
                        .entrance(appeared, delay: 0)
                }
                if !results.lastScanWasComplete {
                    partialScanNotice
                        .entrance(appeared, delay: 0)
                }

                HStack(spacing: Theme.cardGap) {
                    reclaimableCard
                        .frame(maxWidth: .infinity)
                        .entrance(appeared, delay: 0.03)
                    diskCard
                        .frame(width: 350)
                        .entrance(appeared, delay: 0.08)
                }
                .fixedSize(horizontal: false, vertical: true)

                categoryGrid
                    .entrance(appeared, delay: 0.13)

                HStack(alignment: .top, spacing: Theme.cardGap) {
                    biggestCard
                        .frame(maxWidth: .infinity)
                        .entrance(appeared, delay: 0.18)
                    // Lifetime/last/next stats live in the global footer;
                    // the column only appears when it has cards to show.
                    if !projects.devRoots.isEmpty || !results.manualTargets.isEmpty {
                        VStack(spacing: Theme.Space.s12) {
                            if !projects.devRoots.isEmpty {
                                projectsCard
                            }
                            if !results.manualTargets.isEmpty {
                                attentionCard
                            }
                        }
                        .frame(width: 350)
                        .entrance(appeared, delay: 0.22)
                    }
                }
            }
            .padding(.horizontal, Theme.contentMargin)
            .padding(.top, Theme.Space.s20)
            .padding(.bottom, Theme.Space.s32)
        }
        .onAppear { withAnimation(Theme.springy) { appeared = true } }
    }

    // MARK: - Notices

    private var partialScanNotice: some View {
        Label(
            localized(
                "overview.partialScanNotice",
                defaultValue: "Scan stopped early — the sizes below cover only what was measured before stopping."
            ),
            systemImage: "exclamationmark.circle"
        )
        .themeFont(.body)
        .foregroundStyle(Theme.cautionTitle)
        .padding(.horizontal, Theme.Space.s14)
        .padding(.vertical, Theme.Space.s10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.caution.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusInset))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusInset)
                .strokeBorder(Theme.caution.opacity(0.3), lineWidth: 0.5)
        }
    }

}

// MARK: - Previews

#if DEBUG
#Preview(traits: .fixedLayout(width: 1060, height: 900)) {
    OverviewView(
        openCategory: { _ in }, openTarget: { _ in },
        reviewEverything: {}, reclaimSafe: {}, openProjects: {}
    )
        .background(Theme.background)
        .appEnvironment(PreviewData.scanned())
        .preferredColorScheme(.dark)
}
#endif
