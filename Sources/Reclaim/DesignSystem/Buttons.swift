//
//  Buttons.swift
//  Reclaim
//
//  The app's three button voices: accent-filled primary, quiet
//  secondary, and the destructive confirmation. All share the same
//  hover/press motion so controls feel like one family.
//

import SwiftUI

/// Emerald call-to-action. `prominent` is the hero size; the compact
/// variant fits toolbars and cards.
struct PrimaryButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: prominent ? 14.5 : 13, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, prominent ? 22 : 15)
            .frame(height: prominent ? 38 : 31)
            .background(
                Theme.accentGradient,
                in: RoundedRectangle(cornerRadius: prominent ? 10 : Theme.radiusControl)
            )
            .overlay {
                RoundedRectangle(cornerRadius: prominent ? 10 : Theme.radiusControl)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
                    .blendMode(.plusLighter)
                    .mask(alignment: .top) {
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top, endPoint: .center
                        )
                    }
            }
            .shadow(
                color: Theme.accent.opacity(isEnabled ? (prominent ? 0.45 : 0.3) : 0),
                radius: prominent ? 12 : 6, y: prominent ? 8 : 3
            )
            .brightness(isHovered && isEnabled ? 0.05 : 0)
            .saturation(isEnabled ? 1 : 0.2)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
            .animation(Theme.quick, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

/// Quiet, translucent counterpart to the primary button. `compact`
/// matches the 26 pt toolbar controls.
struct SecondaryButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12.5 : 13, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, compact ? 11 : 15)
            .frame(height: compact ? 26 : 31)
            .controlGlass(
                cornerRadius: compact ? Theme.radiusChip : Theme.radiusControl,
                fallback: Color.white.opacity(isHovered && isEnabled ? 0.13 : 0.08)
            )
            .overlay {
                RoundedRectangle(cornerRadius: compact ? Theme.radiusChip : Theme.radiusControl)
                    .strokeBorder(Theme.controlFill, lineWidth: 0.5)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
            .animation(Theme.quick, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

/// Red gradient for permanent-deletion confirmations.
struct DangerButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .frame(height: 30)
            .background(
                Theme.dangerGradient,
                in: RoundedRectangle(cornerRadius: Theme.radiusControl)
            )
            .brightness(isHovered ? 0.06 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
            .animation(Theme.quick, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var rcPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var rcPrimaryProminent: PrimaryButtonStyle { PrimaryButtonStyle(prominent: true) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var rcSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static var rcSecondaryCompact: SecondaryButtonStyle { SecondaryButtonStyle(compact: true) }
}

extension ButtonStyle where Self == DangerButtonStyle {
    static var rcDanger: DangerButtonStyle { DangerButtonStyle() }
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
        Button("Scan this Mac") {}.buttonStyle(.rcPrimaryProminent)
        Button("Reclaim 82.6 GB") {}.buttonStyle(.rcPrimary)
        Button("Review everything") {}.buttonStyle(.rcSecondary)
        Button("Delete Permanently") {}.buttonStyle(.rcDanger)
    }
    .padding(40)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
