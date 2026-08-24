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
        VStack(alignment: .leading, spacing: Theme.Space.s5) {
            Text(localized("inspector.wontDeleteTitle", defaultValue: "Reclaim won’t delete this"))
                .themeFont(.warningTitle)
                .foregroundStyle(Theme.cautionTitle)
            Text(target.manualInstructions ?? "")
                .themeFont(.meta)
                .lineSpacing(3)
                .foregroundStyle(Theme.textSubtle)

            if let command = target.manualCommand {
                HStack(spacing: Theme.Space.s8) {
                    Text(command)
                        .font(Theme.mono())
                        .foregroundStyle(Theme.textCommandSnippet)
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
                    .themeFont(.miniButtonLabel)
                    .foregroundStyle(Theme.accentLabel)
                    .contentTransition(.opacity)
                }
                .padding(.horizontal, Theme.Space.s9)
                .padding(.vertical, Theme.Space.s7)
                .background(Theme.codeSnippetFill, in: RoundedRectangle(cornerRadius: Theme.radiusIconChip))
                .padding(.top, Theme.Space.s5)
            }
        }
        .padding(Theme.Space.s12)
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
