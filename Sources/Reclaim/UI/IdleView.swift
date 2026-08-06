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
            Text("Reclaim \(appVersion)")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Theme.accentLabel)
                .entrance(appeared, delay: 0)

            Text("Reclaim the space your tools quietly keep.")
                .font(.system(size: 40, weight: .bold))
                .lineSpacing(2)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: 480, alignment: .leading)
                .padding(.top, 16)
                .entrance(appeared, delay: 0.05)

            Text("Reclaim checks a curated catalogue of known cache and scratch locations, tells you what each one is and what it costs to lose, then cleans only what you select.")
                .font(.system(size: 14.5))
                .lineSpacing(4)
                .foregroundStyle(Theme.textBody)
                .frame(maxWidth: 430, alignment: .leading)
                .padding(.top, 16)
                .entrance(appeared, delay: 0.1)

            HStack(spacing: 14) {
                Button("Scan this Mac") {
                    model.scanAll()
                }
                .buttonStyle(.rcPrimaryProminent)
                .keyboardShortcut(.defaultAction)

                Text("Read-only — nothing is removed by scanning")
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
            safetyNote(.safe, "Regenerated automatically. Build caches, indexes, logs.")
            safetyNote(.caution, "Restorable, but re-downloading or losing history costs something.")
            safetyNote(.destructive, "Removes things you made, like emulators. Never preselected.")
        }
    }

    private func safetyNote(_ level: SafetyLevel, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(level.color)
                .frame(width: 7, height: 7)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 2.5 }
            Text("\(Text(level.title).fontWeight(.semibold).foregroundStyle(Theme.textPrimary)) — \(text)")
                .font(Theme.body)
                .foregroundStyle(Color(hex: 0x8E8E95))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: - Right column

    private var catalogueColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            catalogueCard
                .entrance(appeared, delay: 0.12)

            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textBody)
                    .frame(width: 16, height: 16)
                    .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 5))
                Text("Nothing is removed without your confirmation, and everything goes to the Trash by default. Credentials, settings and plugins are never in the catalogue.")
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
                SectionLabel("What Reclaim looks at")
                Spacer()
                Text("Not measured yet")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textQuaternary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 15)
            .padding(.bottom, 13)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            }

            ForEach(ToolCategory.allCases) { category in
                catalogueRow(category)
            }

            diskFooter
                .padding(.horizontal, 18)
                .padding(.top, 13)
                .padding(.bottom, 15)
        }
        .card(radius: 14, fill: Theme.cardFillQuiet)
        .shadow(color: .black.opacity(0.4), radius: 20, y: 12)
    }

    private func catalogueRow(_ category: ToolCategory) -> some View {
        let targets = TargetRegistry.targets(in: category)
        return HStack(spacing: 12) {
            CategoryTile(category: category, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(targets.prefix(3).map(\.name).joined(separator: " · "))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 10)
            Text("\(targets.count) locations")
                .font(Theme.caption)
                .foregroundStyle(Theme.textQuaternary)
            StripedPlaceholder()
                .frame(width: 34, height: 4)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
        }
    }

    private var diskFooter: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Macintosh HD")
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
        return "\(space.usedBytes.wholeGB) used of \(space.totalBytes.wholeGB)"
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
