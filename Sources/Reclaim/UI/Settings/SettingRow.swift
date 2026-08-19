//
//  SettingRow.swift
//  Reclaim
//
//  One switch row inside a settings card.
//

import SwiftUI

struct SettingRow: View {
    let title: String
    let help: String
    @Binding var isOn: Bool
    var isLast: Bool

    init(_ title: String, help: String, isOn: Binding<Bool>, isLast: Bool = false) {
        self.title = title
        self.help = help
        self._isOn = isOn
        self.isLast = isLast
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .themeFont(.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(help)
                    .scaledFont(size: 12)
                    .lineSpacing(2.5)
                    .foregroundStyle(Color(hex: 0x8E8E95))
            }
        }
        .toggleStyle(.rcSwitch)
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Theme.separator).frame(height: 1)
            }
        }
    }
}
