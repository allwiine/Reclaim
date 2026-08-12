//
//  IdleView.swift
//  Reclaim
//
//  The pre-scan hero: what Reclaim does, the safety ground rules, a
//  preview of the catalogue, and the single call to action.
//

import AppKit
import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct IdleView: View {
    @Environment(AppModel.self) private var model
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 0) {
            pitch
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 52)
                .padding(.trailing, 44)

            catalogueColumn
                .frame(maxWidth: .infinity)
                .padding(.trailing, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .topLeading) {
            // Soft emerald glow anchored to the headline corner.
            RadialGradient(
                colors: [Theme.accentGlow.opacity(0.16), .clear],
                center: .init(x: 0.12, y: 0),
                startRadius: 0, endRadius: 640
            )
            .ignoresSafeArea()
        }
        .onAppear { withAnimation(Theme.springy) { appeared = true } }
    }

    // MARK: - Left column

    private var pitch: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(versionBadge)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Theme.accentLabel)
                .entrance(appeared, delay: 0)

            Text(localized("idle.headline", defaultValue: "Reclaim the space your tools quietly keep."))
                .font(.system(size: 40, weight: .bold))
                .lineSpacing(2)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: 480, alignment: .leading)
                .padding(.top, 16)
                .entrance(appeared, delay: 0.05)

            Text(localized(
                "idle.pitch",
                defaultValue: "Reclaim checks a curated catalogue of known cache and scratch locations, tells you what each one is and what it costs to lose, then cleans only what you select."
            ))
            .font(.system(size: 14.5))
            .lineSpacing(4)
            .foregroundStyle(Theme.textBody)
            .frame(maxWidth: 430, alignment: .leading)
            .padding(.top, 16)
            .entrance(appeared, delay: 0.1)

            HStack(spacing: 14) {
                Button(localized("idle.scanButton", defaultValue: "Scan this Mac")) {
                    model.scanAll()
                }
                .buttonStyle(.rcPrimaryProminent)
                .keyboardShortcut(.defaultAction)

                Text(localized(
                    "idle.readOnlyNote",
                    defaultValue: "Read-only — nothing is removed by scanning"
                ))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textTertiary)
            }
            .padding(.top, 30)
            .entrance(appeared, delay: 0.16)

            safetyNotes
                .padding(.top, 26)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.divider).frame(height: 1).offset(y: -13)
                }
                .padding(.top, 27)
                .frame(maxWidth: 460, alignment: .leading)
                .entrance(appeared, delay: 0.22)
        }
    }

    private var safetyNotes: some View {
        VStack(alignment: .leading, spacing: 11) {
            safetyNote(.safe, localized(
                "idle.safetyNote.safe",
                defaultValue: "Regenerated automatically. Build caches, indexes, logs."
            ))
            safetyNote(.caution, localized(
                "idle.safetyNote.caution",
                defaultValue: "Restorable, but re-downloading or losing history costs something."
            ))
            safetyNote(.destructive, localized(
                "idle.safetyNote.destructive",
                defaultValue: "Removes things you made, like emulators. Never preselected."
            ))
        }
    }

    private func safetyNote(_ level: SafetyLevel, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(level.color)
                .frame(width: 7, height: 7)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 2.5 }
            (Text(level.title).fontWeight(.semibold).foregroundStyle(Theme.textPrimary)
                + Text(verbatim: ": ")
                + Text(text))
                .font(Theme.body)
                .foregroundStyle(Color(hex: 0x8E8E95))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Reclaim 1.2.0" from the bundle, or plain "Reclaim" when there
    /// is no bundle version (e.g. `swift run`) — a version is shown
    /// automatically or not at all, never a hardcoded guess.
    private var versionBadge: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        else {
            return localized("app.name", defaultValue: "Reclaim")
        }
        return localized("idle.versionBadge", defaultValue: "Reclaim \(version)")
    }

    // MARK: - Right column

    private var catalogueColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            catalogueCard
                .entrance(appeared, delay: 0.12)

            HStack(alignment: .center, spacing: 10) {
                // A trust statement, not a setting: a sealed checkmark in
                // the accent color, never anything that reads as a checkbox.
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.accent)
                Text(localized(
                    "idle.trustNote",
                    defaultValue: "Nothing is removed without your confirmation, and everything goes to the Trash by default. Credentials, settings and plugins are never in the catalogue."
                ))
                .font(Theme.footnote)
                .lineSpacing(2.5)
                .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 4)
            .entrance(appeared, delay: 0.2)
        }
        .frame(maxWidth: 460)
    }

    private var catalogueCard: some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel(localized("idle.catalogueTitle", defaultValue: "What Reclaim looks at"))
                Spacer()
                Text(localized("accessibility.notMeasuredYet", defaultValue: "Not measured yet"))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textQuaternary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 15)
            .padding(.bottom, 13)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            }

            // Breadth at a glance, not a row per category: the card's
            // height must stay bounded as the catalogue grows, so the
            // grid caps at `maxVisibleChips` and folds the rest into a
            // "+N more" chip instead of stretching forever.
            VStack(alignment: .leading, spacing: 13) {
                Text(localized(
                    "idle.catalogueSummary",
                    defaultValue: "\(TargetRegistry.all.count) known locations across \(ToolCategory.allCases.count) tool categories"
                ))
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 185), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(visibleChipCategories) { category in
                        categoryChip(category)
                    }
                    if hiddenChipCount > 0 {
                        moreChip
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
            }

            idleProjectsRow
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                }

            diskFooter
                .padding(.horizontal, 18)
                .padding(.top, 13)
                .padding(.bottom, 15)
        }
        .card(radius: 14, fill: Theme.cardFillQuiet)
        .shadow(color: .black.opacity(0.4), radius: 20, y: 12)
    }

    /// The dev-folder feature's slot in the catalogue card: configured
    /// folders when the feature is set up, an inline setup button when
    /// it is not.
    private var idleProjectsRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0xB8B8BF))
                .frame(width: 26, height: 26)
                .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(localized("sidebar.projects", defaultValue: "Projects"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(model.devRoots.isEmpty
                    ? localized(
                        "idle.projectsPitch",
                        defaultValue: "Find git repos, node_modules and build folders in your own projects."
                    )
                    : model.devRoots
                        .map { ($0.path as NSString).abbreviatingWithTildeInPath }
                        .joined(separator: " · "))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 10)
            if model.devRoots.isEmpty {
                Button(localized("settings.addDevFolder", defaultValue: "Add folder…")) {
                    for url in DevFolderPicker.pickFolders() {
                        model.addDevRoot(url)
                    }
                }
                .buttonStyle(.rcSecondary)
            } else {
                StripedPlaceholder()
                    .frame(width: 34, height: 4)
            }
        }
    }

    /// Ceiling on category chips before the card folds into "+N more".
    private static let maxVisibleChips = 14

    private var visibleChipCategories: [ToolCategory] {
        let all = ToolCategory.allCases
        guard all.count > Self.maxVisibleChips else { return all }
        return Array(all.prefix(Self.maxVisibleChips - 1))
    }

    private var hiddenChipCount: Int {
        ToolCategory.allCases.count - visibleChipCategories.count
    }

    private func categoryChip(_ category: ToolCategory) -> some View {
        HStack(spacing: 8) {
            CategoryTile(category: category, size: 22)
            Text(category.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color(hex: 0xC8C8CF))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.05), lineWidth: 0.5)
        }
    }

    private var moreChip: some View {
        HStack(spacing: 8) {
            Text(localized("idle.moreCategories", defaultValue: "\(hiddenChipCount) more"))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.04), lineWidth: 0.5)
        }
    }

    private var diskFooter: some View {
        VStack(spacing: 8) {
            HStack {
                Text(model.volumeDisplayName)
                    .font(Theme.footnote)
                    .foregroundStyle(Color(hex: 0x98989F))
                Spacer()
                Text(diskLabel)
                    .font(Theme.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            SegmentedBar(segments: diskSegments)
        }
    }

    private var diskLabel: String {
        guard let space = model.volumeSpace else { return "—" }
        return localized(
            "disk.usedOfTotal",
            defaultValue: "\(space.usedBytes.wholeGB) used of \(space.totalBytes.wholeGB)"
        )
    }

    private var diskSegments: [MeterSegment] {
        guard let space = model.volumeSpace, space.totalBytes > 0 else { return [] }
        let used = Double(space.usedBytes) / Double(space.totalBytes)
        return [MeterSegment(id: "used", fraction: used, color: .white.opacity(0.22))]
    }
}

// MARK: - Entrance animation

/// Fade-and-rise entrance used to stagger hero content in.
private struct Entrance: ViewModifier {
    let shown: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .animation(Theme.springy.delay(delay), value: shown)
    }
}

extension View {
    func entrance(_ shown: Bool, delay: Double) -> some View {
        modifier(Entrance(shown: shown, delay: delay))
    }
}

// MARK: - Previews

#if DEBUG
#Preview(traits: .fixedLayout(width: 1060, height: 810)) {
    IdleView()
        .background(Theme.background)
        .environment(PreviewData.idle())
        .preferredColorScheme(.dark)
}
#endif
