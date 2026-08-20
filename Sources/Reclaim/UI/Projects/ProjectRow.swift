//
//  ProjectRow.swift
//  Reclaim
//
//  One project row: tri-state checkbox, name + stale badge + activity,
//  artifact size + relative bar.
//

import AppKit
import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    let project: DiscoveredProject
    let isInspected: Bool
    let maxBytes: Int64
    let inspect: () -> Void

    var body: some View {
        Button(action: inspect) {
            HStack(spacing: 12) {
                checkbox

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(project.name)
                            .scaledFont(size: 13.5, weight: .medium)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if model.projects.isProjectStale(project) {
                            StaleBadge()
                        }
                    }
                    Text(activityLine)
                        .themeFont(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                trailing
                    .frame(width: 96, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                isInspected ? Color.white.opacity(0.075) : .clear,
                in: RoundedRectangle(cornerRadius: Theme.radiusInset)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusInset))
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: Theme.radiusInset, color: Color.white.opacity(0.055))
        .animation(Theme.quick, value: isInspected)
        .contextMenu { contextMenu }
    }

    private var activityLine: String {
        var parts: [String] = [
            (project.url.path as NSString).abbreviatingWithTildeInPath,
        ]
        if let edited = project.lastEditDate {
            parts.append(localized(
                "projects.lastEdited",
                defaultValue: "Edited \(edited.formatted(.relative(presentation: .named)))"
            ))
        }
        if let git = project.lastGitActivityDate {
            parts.append(localized(
                "projects.lastCommit",
                defaultValue: "Git activity \(git.formatted(.relative(presentation: .named)))"
            ))
        }
        return parts.joined(separator: " · ")
    }

    private var checkbox: some View {
        Toggle(
            localized("browser.selectAccessibility", defaultValue: "Select \(project.name)"),
            isOn: Binding(
                get: { model.projects.isProjectSelected(project) },
                set: { model.projects.setProjectSelected(project, $0) }
            )
        )
        .toggleStyle(CheckboxToggleStyle(mixed: model.projects.isProjectPartiallySelected(project)))
        .labelsHidden()
        .disabled(!model.projects.isProjectSelectable(project))
        .opacity(model.projects.isProjectSelectable(project) ? 1 : 0.35)
    }

    @ViewBuilder
    private var trailing: some View {
        if project.artifactBytes > 0 {
            VStack(alignment: .trailing, spacing: 5) {
                Text(project.artifactBytes.formattedBytesCompact)
                    .scaledFont(size: 13, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                MiniBar(
                    fraction: maxBytes > 0
                        ? Double(project.artifactBytes) / Double(maxBytes) : 0,
                    color: Theme.safe
                )
            }
        } else {
            Text(verbatim: "—")
                .scaledFont(size: 12)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(localized("projects.revealInFinder", defaultValue: "Reveal in Finder")) {
            NSWorkspace.shared.activateFileViewerSelecting([project.url])
        }
        Button(localized("browser.copyPaths", defaultValue: "Copy \(1) Paths")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(project.url.path, forType: .string)
        }
    }
}
