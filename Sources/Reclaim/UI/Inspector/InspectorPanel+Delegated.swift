//
//  InspectorPanel+Delegated.swift
//  Reclaim
//
//  For tool-managed items: the "Reclaim won't delete this" card with
//  its manual instructions, and the command-line info line.
//

import AppKit
import ReclaimKit
import SwiftUI

extension InspectorPanel {
    func delegatedCard(for target: CleanupTarget) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(localized("inspector.wontDeleteTitle", defaultValue: "Reclaim won’t delete this"))
                .scaledFont(size: 12, weight: .semibold)
                .foregroundStyle(Theme.cautionTitle)
            Text(target.manualInstructions ?? "")
                .scaledFont(size: 12)
                .lineSpacing(3)
                .foregroundStyle(Color(hex: 0xB8B8BF))

            if let command = target.manualCommand {
                HStack(spacing: 8) {
                    Text(command)
                        .font(Theme.mono())
                        .foregroundStyle(Color(hex: 0xDCDCE2))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(copied
                        ? localized("action.copied", defaultValue: "Copied")
                        : localized("action.copy", defaultValue: "Copy")
                    ) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                        withAnimation(Theme.quick) { copied = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1.4))
                            withAnimation(Theme.quick) { copied = false }
                        }
                    }
                    .buttonStyle(.plain)
                    .scaledFont(size: 11, weight: .medium)
                    .foregroundStyle(Theme.accentLabel)
                    .contentTransition(.opacity)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                .padding(.top, 5)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.caution.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusInset))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusInset)
                .strokeBorder(Theme.caution.opacity(0.3), lineWidth: 0.5)
        }
    }

    func commandInfo(_ spec: CommandSpec) -> some View {
        Label {
            Text(localized("inspector.cleansByRunning", defaultValue: "Cleans by running"))
                + Text(verbatim: " ")
                + Text(spec.displayCommand).font(Theme.mono())
        } icon: {
            Image(systemName: "terminal")
        }
        .themeFont(.caption)
        .foregroundStyle(Theme.textSecondary)
    }
}
