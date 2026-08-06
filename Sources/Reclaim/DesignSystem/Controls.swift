//
//  Controls.swift
//  Reclaim
//
//  Small reusable pieces of the design language: cards, section
//  labels, badges, category tiles, the checkbox and the switch.
//

import ReclaimKit
import SwiftUI

// MARK: - Card

/// Standard raised card: soft fill + inset hairline.
struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.radiusCard
    var fill: Color = Theme.cardFill

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            }
    }
}

extension View {
    func card(radius: CGFloat = Theme.radiusCard, fill: Color = Theme.cardFill) -> some View {
        modifier(CardBackground(radius: radius, fill: fill))
    }
}

// MARK: - Section label

/// Uppercase tracking label above cards and lists.
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.labelFont)
            .tracking(Theme.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textLabel)
    }
}

// MARK: - Badge

/// Colored capsule communicating a target's risk class.
struct Badge: View {
    let kind: BadgeKind

    init(_ kind: BadgeKind) { self.kind = kind }

    init(for target: CleanupTarget) { self.kind = BadgeKind(for: target) }

    var body: some View {
        Text(kind.title)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(kind.color)
            .padding(.horizontal, 7)
            .frame(height: 16)
            .background(kind.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(kind.color.opacity(0.3), lineWidth: 0.5)
            }
            .help(kind.explanation)
            .accessibilityLabel("Safety: \(kind.title)")
    }
}

// MARK: - Category tile

/// Rounded letter tile in a category's color.
struct CategoryTile: View {
    let category: ToolCategory
    var size: CGFloat = 22

    var body: some View {
        Text(category.letter)
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(category.color)
            .frame(width: size, height: size)
            .background(
                category.color.opacity(0.16),
                in: RoundedRectangle(cornerRadius: size * 0.27)
            )
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.27)
                    .strokeBorder(category.color.opacity(0.3), lineWidth: 0.5)
            }
            .accessibilityLabel(category.title)
    }
}

// MARK: - Checkbox

/// 17-pt selection checkbox with the accent gradient when ticked.
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(configuration.isOn ? 0 : 0.06))
                if configuration.isOn {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Theme.accentGradient)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .opacity(configuration.isOn ? 1 : 0)
                    .scaleEffect(configuration.isOn ? 1 : 0.4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
            }
            .frame(width: 17, height: 17)
            .animation(Theme.quick, value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

extension ToggleStyle where Self == CheckboxToggleStyle {
    static var rcCheckbox: CheckboxToggleStyle { CheckboxToggleStyle() }
}

// MARK: - Switch

/// The design's 38×22 settings switch.
struct SwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                configuration.isOn.toggle()
            } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(Color.white.opacity(configuration.isOn ? 0 : 0.12))
                    if configuration.isOn {
                        Capsule().fill(Theme.accentGradient)
                    }
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                        .padding(2)
                }
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                }
                .frame(width: 38, height: 22)
                .animation(.spring(response: 0.28, dampingFraction: 0.8), value: configuration.isOn)
            }
            .buttonStyle(.plain)
        }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

extension ToggleStyle where Self == SwitchToggleStyle {
    static var rcSwitch: SwitchToggleStyle { SwitchToggleStyle() }
}

// MARK: - Hover row

/// Adds the standard hover highlight + pointer affordance to rows.
struct HoverHighlight: ViewModifier {
    var radius: CGFloat = Theme.radiusControl
    var color: Color = Theme.hoverFill
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isHovered ? color : .clear, in: RoundedRectangle(cornerRadius: radius))
            .animation(Theme.quick, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    func hoverHighlight(
        radius: CGFloat = Theme.radiusControl, color: Color = Theme.hoverFill
    ) -> some View {
        modifier(HoverHighlight(radius: radius, color: color))
    }
}

// MARK: - Previews

#Preview("Controls", traits: .sizeThatFitsLayout) {
    @Previewable @State var checked = true
    @Previewable @State var enabled = true

    VStack(alignment: .leading, spacing: 18) {
        SectionLabel("Reclaimable")
        HStack(spacing: 8) {
            Badge(.safety(.safe))
            Badge(.safety(.caution))
            Badge(.safety(.destructive))
            Badge(.delegated)
        }
        HStack(spacing: 8) {
            ForEach(ToolCategory.allCases) { CategoryTile(category: $0) }
        }
        Toggle("Select", isOn: $checked).toggleStyle(.rcCheckbox)
        Toggle(isOn: $enabled) {
            Text("Move items to the Trash")
                .font(Theme.rowTitle)
                .foregroundStyle(Theme.textPrimary)
        }
        .toggleStyle(.rcSwitch)
        .frame(width: 260)
    }
    .padding(40)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
