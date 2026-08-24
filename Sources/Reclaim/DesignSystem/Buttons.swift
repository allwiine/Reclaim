//
//  Buttons.swift
//  Reclaim
//
//  The app's button voices, centralized. They use macOS 26 Liquid Glass
//  as the material (via `glassEffect`) but through a small custom style
//  so the app controls what the native `.glassProminent` will not: a
//  dark on-accent label on the green CTA, matched heights between the
//  primary and secondary in each tier, and a readable disabled state.
//  The header-strip chip is the one remaining bespoke voice.
//

import SwiftUI

// MARK: - Button voices

/// A Liquid Glass button with app-controlled tint, label colour and
/// height. `kind` selects the colour role; `height`/`fontSize` set the
/// tier so a primary and its secondary line up.
struct GlassButton: ButtonStyle {
    enum Kind { case primary, danger, neutral }
    let kind: Kind
    var height: CGFloat = 34
    var fontSize: CGFloat = 13
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(size: fontSize, weight: .semibold)
            // A button label never wraps: the button takes its ideal
            // width and neighbouring text absorbs the squeeze instead.
            // Without this, a tight row (the confirm footer in longer
            // locales) compresses the label onto two lines.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(labelColor)
            .padding(.horizontal, height * 0.62)
            .frame(height: height)
            .glassEffect(glass, in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
    }

    /// Disabled buttons drop their tint to a plain glass pill so the
    /// muted label stays legible.
    private var glass: Glass {
        guard isEnabled else { return .regular }
        switch kind {
        case .primary: return .regular.tint(Theme.accent).interactive()
        case .danger: return .regular.tint(Theme.dangerWarn).interactive()
        case .neutral: return .regular.interactive()
        }
    }

    private var labelColor: Color {
        guard isEnabled else { return Theme.textQuaternary }
        switch kind {
        case .primary: return Theme.onAccent
        case .danger: return .white
        case .neutral: return Theme.textPrimary
        }
    }
}

extension View {
    /// Primary call-to-action: green glass, dark label.
    func rcPrimary() -> some View { buttonStyle(GlassButton(kind: .primary)) }

    /// Hero-sized primary (the idle "Scan this Mac" CTA).
    func rcPrimaryProminent() -> some View {
        buttonStyle(GlassButton(kind: .primary, height: 44, fontSize: 15))
    }

    /// Toolbar-sized primary (the compact "Reclaim" action).
    func rcPrimaryCompact() -> some View {
        buttonStyle(GlassButton(kind: .primary, height: 28, fontSize: 12.5))
    }

    /// Secondary: neutral clear glass — same height as `rcPrimary`.
    func rcSecondary() -> some View { buttonStyle(GlassButton(kind: .neutral)) }

    /// Toolbar-sized secondary — same height as `rcPrimaryCompact`.
    func rcSecondaryCompact() -> some View {
        buttonStyle(GlassButton(kind: .neutral, height: 28, fontSize: 12.5))
    }

    /// Permanent-deletion CTA: red glass, white label.
    func rcDanger() -> some View { buttonStyle(GlassButton(kind: .danger)) }
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
