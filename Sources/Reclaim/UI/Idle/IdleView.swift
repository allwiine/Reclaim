//
//  IdleView.swift
//  Reclaim
//
//  The pre-scan hero: what Reclaim does, the safety ground rules, a
//  preview of the catalogue, and the single call to action.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct IdleView: View {
    @Environment(AppModel.self) var model
    @State var appeared = false

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
                .scaledFont(size: 11, weight: .bold)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Theme.accentLabel)
                .entrance(appeared, delay: 0)

            Text(localized("idle.headline", defaultValue: "Reclaim the space your tools quietly keep."))
                .scaledFont(size: 40, weight: .bold)
                .lineSpacing(2)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: 480, alignment: .leading)
                .padding(.top, 16)
                .entrance(appeared, delay: 0.05)

            Text(localized(
                "idle.pitch",
                defaultValue: "Reclaim checks a curated catalogue of known cache and scratch locations, tells you what each one is and what it costs to lose, then cleans only what you select."
            ))
            .scaledFont(size: 14.5)
            .lineSpacing(4)
            .foregroundStyle(Theme.textBody)
            .frame(maxWidth: 430, alignment: .leading)
            .padding(.top, 16)
            .entrance(appeared, delay: 0.1)

            HStack(spacing: 14) {
                Button(localized("idle.scanButton", defaultValue: "Scan this Mac")) {
                    model.scanner.scanAll()
                }
                .rcPrimaryProminent()
                .keyboardShortcut(.defaultAction)

                Text(localized(
                    "idle.readOnlyNote",
                    defaultValue: "Read-only — nothing is removed by scanning"
                ))
                .scaledFont(size: 12.5)
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
                .themeFont(.body)
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
