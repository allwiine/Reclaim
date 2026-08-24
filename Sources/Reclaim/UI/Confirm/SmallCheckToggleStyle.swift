//
//  SmallCheckToggleStyle.swift
//  Reclaim
//
//  16-pt checkbox with a trailing label, used in the confirm sheet's
//  footer.
//

import SwiftUI

struct SmallCheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: Theme.Space.s8) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radiusBadge)
                        .fill(configuration.isOn ? Color.white.opacity(0) : Theme.hoverFill)
                    if configuration.isOn {
                        RoundedRectangle(cornerRadius: Theme.radiusBadge).fill(Theme.accentGradient)
                        Image(systemName: "checkmark")
                            .themeFont(.checkmarkIcon)
                            .foregroundStyle(Theme.onAccent)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radiusBadge)
                        .strokeBorder(Theme.borderFloating, lineWidth: 0.5)
                }
                .frame(width: 16, height: 16)
                .animation(Theme.quick, value: configuration.isOn)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}
