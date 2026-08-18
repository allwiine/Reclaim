//
//  Buttons.swift
//  Reclaim
//
//  The primary/secondary/danger buttons use macOS 26's native Liquid
//  Glass styles directly at the call sites (`.glassProminent` tinted by
//  the app's accent, `.glass`, and `.glassProminent` with a red tint).
//  The one bespoke voice left is the small header-strip chip.
//

import SwiftUI

// MARK: - Button voices (native Liquid Glass, centralized here)

extension View {
    /// Primary call-to-action: accent-tinted prominent Liquid Glass.
    /// (The app sets its accent tint at the root, so this reads green;
    /// the red danger voice overrides the tint locally.)
    func rcPrimary() -> some View { buttonStyle(.glassProminent) }

    /// Hero-sized primary (the idle "Scan this Mac" CTA).
    func rcPrimaryProminent() -> some View {
        buttonStyle(.glassProminent).controlSize(.large)
    }

    /// Toolbar-sized primary (the compact "Reclaim" action).
    func rcPrimaryCompact() -> some View {
        buttonStyle(.glassProminent).controlSize(.small)
    }

    /// Secondary: clear Liquid Glass.
    func rcSecondary() -> some View { buttonStyle(.glass) }

    /// Toolbar-sized secondary.
    func rcSecondaryCompact() -> some View {
        buttonStyle(.glass).controlSize(.small)
    }

    /// Permanent-deletion CTA: red-tinted prominent glass.
    func rcDanger() -> some View { buttonStyle(.glassProminent).tint(.red) }
}

// MARK: - Strip chip

/// Small chip button for a list header strip ("Select all", "Clear").
struct StripChipButtonStyle: ButtonStyle {
    var plain = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(
                plain
                    ? (isHovered && isEnabled ? Theme.textPrimary : Theme.textSecondary)
                    : Color(hex: 0xD5D5DB)
            )
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background {
                if !plain {
                    RoundedRectangle(cornerRadius: Theme.radiusChip)
                        .fill(Color.white.opacity(isHovered ? 0.12 : 0.07))
                    RoundedRectangle(cornerRadius: Theme.radiusChip)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
                }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
            .animation(Theme.quick, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Previews

#Preview("Buttons", traits: .sizeThatFitsLayout) {
    VStack(spacing: 16) {
        Button("Scan this Mac") {}.buttonStyle(.glassProminent).controlSize(.large)
        Button("Reclaim 82.6 GB") {}.buttonStyle(.glassProminent)
        Button("Review everything") {}.buttonStyle(.glass)
        Button("Delete Permanently") {}.buttonStyle(.glassProminent).tint(.red)
    }
    .tint(Theme.accent)
    .padding(40)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
