//
//  IdleView+Catalogue.swift
//  Reclaim
//
//  The right column: the catalogue card (category chips, the
//  dev-folder projects row) and the disk-usage footer beneath it.
//

import AppKit
import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension IdleView {
    // MARK: - Right column

    var catalogueColumn: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s14) {
            catalogueCard
                .entrance(appeared, delay: 0.12)

            HStack(alignment: .center, spacing: Theme.Space.s10) {
                // A trust statement, not a setting: a sealed checkmark in
                // the accent color, never anything that reads as a checkbox.
                Image(systemName: "checkmark.seal.fill")
                    .themeFont(.trustIcon)
                    .foregroundStyle(Theme.accent)
                Text(localized(
                    "idle.trustNote",
                    defaultValue: "Nothing is removed without your confirmation, and everything goes to the Trash by default. Credentials, settings and plugins are never in the catalogue."
                ))
                .themeFont(.footnote)
                .lineSpacing(2.5)
                .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.Space.s4)
            .entrance(appeared, delay: 0.2)
        }
        .frame(maxWidth: 460)
    }

    private var catalogueCard: some View {
        VStack(spacing: Theme.Space.s0) {
            HStack {
                SectionLabel(localized("idle.catalogueTitle", defaultValue: "What Reclaim looks at"))
                Spacer()
                Text(localized("accessibility.notMeasuredYet", defaultValue: "Not measured yet"))
                    .themeFont(.caption)
                    .foregroundStyle(Theme.textQuaternary)
            }
            .padding(.horizontal, Theme.Space.s18)
            .padding(.top, Theme.Space.s15)
            .padding(.bottom, Theme.Space.s13)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.cardSectionDivider).frame(height: 1)
            }

            // Breadth at a glance, not a row per category: the card's
            // height must stay bounded as the catalogue grows, so the
            // grid caps at `maxVisibleChips` and folds the rest into a
            // "+N more" chip instead of stretching forever.
            VStack(alignment: .leading, spacing: Theme.Space.s13) {
                Text(localized(
                    "idle.catalogueSummary",
                    defaultValue: "\(TargetRegistry.all.count) known locations across \(ToolCategory.allCases.count) tool categories"
                ))
                .themeFont(.body)
                .foregroundStyle(Theme.textSecondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 185), spacing: Theme.Space.s8)],
                    alignment: .leading,
                    spacing: Theme.Space.s8
                ) {
                    ForEach(visibleChipCategories) { category in
                        categoryChip(category)
                    }
                    if hiddenChipCount > 0 {
                        moreChip
                    }
                }
            }
            .padding(.horizontal, Theme.Space.s18)
            .padding(.top, Theme.Space.s14)
            .padding(.bottom, Theme.Space.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.cardSectionDividerFaint).frame(height: 1)
            }

            idleProjectsRow
                .padding(.horizontal, Theme.Space.s18)
                .padding(.vertical, Theme.Space.s12)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.cardSectionDividerFaint).frame(height: 1)
                }

            diskFooter
                .padding(.horizontal, Theme.Space.s18)
                .padding(.top, Theme.Space.s13)
                .padding(.bottom, Theme.Space.s15)
        }
        .card(radius: Theme.radiusHero, fill: Theme.cardFillQuiet)
        .shadow(color: Theme.cardShadow, radius: 20, y: 12)
    }

    /// The dev-folder feature's slot in the catalogue card: configured
    /// folders when the feature is set up, an inline setup button when
    /// it is not.
    private var idleProjectsRow: some View {
        HStack(spacing: Theme.Space.s12) {
            Image(systemName: "folder.badge.gearshape")
                .themeFont(.tileLabel)
                .foregroundStyle(Theme.textSubtle)
                .frame(width: 26, height: 26)
                .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: Theme.radiusChip))
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                Text(localized("sidebar.projects", defaultValue: "Projects"))
                    .themeFont(.amount)
                    .foregroundStyle(Theme.textPrimary)
                Text(projects.devRoots.isEmpty
                    ? localized(
                        "idle.projectsPitch",
                        defaultValue: "Find git repos, node_modules and build folders in your own projects."
                    )
                    : projects.devRoots
                        .map { ($0.path as NSString).abbreviatingWithTildeInPath }
                        .joined(separator: " · "))
                    .themeFont(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 10)
            if projects.devRoots.isEmpty {
                Button(localized("settings.addDevFolder", defaultValue: "Add folder…")) {
                    for url in DevFolderPicker.pickFolders() {
                        projects.addDevRoot(url)
                    }
                }
                .rcSecondary()
            } else {
                StripedPlaceholder()
                    .frame(width: 34, height: 4)
            }
        }
    }

    private var diskFooter: some View {
        VStack(spacing: Theme.Space.s8) {
            HStack {
                Text(results.volumeDisplayName)
                    .themeFont(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(diskLabel)
                    .themeFont(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            SegmentedBar(segments: diskSegments)
        }
    }

    private var diskLabel: String {
        guard let space = results.volumeSpace else { return "—" }
        return localized(
            "disk.usedOfTotal",
            defaultValue: "\(space.usedBytes.wholeGB) used of \(space.totalBytes.wholeGB)"
        )
    }

    private var diskSegments: [MeterSegment] {
        guard let space = results.volumeSpace, space.totalBytes > 0 else { return [] }
        let used = Double(space.usedBytes) / Double(space.totalBytes)
        return [MeterSegment(id: "used", fraction: used, color: Theme.usedTrackIdle)]
    }
}
