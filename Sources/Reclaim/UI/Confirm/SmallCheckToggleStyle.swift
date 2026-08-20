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
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.white.opacity(configuration.isOn ? 0 : 0.07))
                    if configuration.isOn {
                        RoundedRectangle(cornerRadius: 5).fill(Theme.accentGradient)
                        Image(systemName: "checkmark")
                            .scaledFont(size: 8.5, weight: .bold)
                            .foregroundStyle(Theme.onAccent)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
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
