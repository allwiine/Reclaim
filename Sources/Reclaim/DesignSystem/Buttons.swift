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
    /// Primary call-to-action: accent-tinted prominent Liquid Glass with
    /// dark (on-accent) label text. The tint is applied here, per button,
    /// rather than app-wide, so the neutral secondary glass is never
    /// green.
    func rcPrimary() -> some View {
        buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(Theme.accent)
            .foregroundStyle(Theme.onAccent)
    }

    /// Hero-sized primary (the idle "Scan this Mac" CTA).
    func rcPrimaryProminent() -> some View {
        buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .tint(Theme.accent)
            .foregroundStyle(Theme.onAccent)
    }

    /// Toolbar-sized primary (the compact "Reclaim" action).
    func rcPrimaryCompact() -> some View {
        buttonStyle(.glassProminent)
            .controlSize(.regular)
            .tint(Theme.accent)
            .foregroundStyle(Theme.onAccent)
    }

    /// Secondary: neutral clear Liquid Glass (never tinted).
    func rcSecondary() -> some View {
        buttonStyle(.glass).controlSize(.large)
    }

    /// Toolbar-sized secondary.
    func rcSecondaryCompact() -> some View {
        buttonStyle(.glass).controlSize(.regular)
    }

    /// Permanent-deletion CTA: red-tinted prominent glass, white label.
    func rcDanger() -> some View {
        buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(.red)
            .foregroundStyle(.white)
    }
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
        Button("Scan this Mac") {}.rcPrimaryProminent()
        Button("Reclaim 82.6 GB") {}.rcPrimary()
        Button("Review everything") {}.rcSecondary()
        Button("Delete Permanently") {}.rcDanger()
    }
    .padding(40)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
