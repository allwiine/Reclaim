//
//  ProjectInspectorPanel+Pieces.swift
//  Reclaim
//
//  The project inspector's identity pieces: its folder tile, size
//  headline, last-activity lines, and the file-path chip.
//

import AppKit
import ReclaimKit
import SwiftUI

extension ProjectInspectorPanel {
    // MARK: - Pieces

    var projectTile: some View {
        Image(systemName: "folder.badge.gearshape")
            .scaledFont(size: 15, weight: .semibold)
            .foregroundStyle(Theme.safe)
            .frame(width: 34, height: 34)
            .background(Theme.safe.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Theme.safe.opacity(0.3), lineWidth: 0.5)
            }
    }

    @ViewBuilder
    func sizeHeadline(for project: DiscoveredProject) -> some View {
        if project.artifactBytes > 0 {
            let parts = project.artifactBytes.byteParts
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(parts.value)
                    .font(Theme.heroNumber(27))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(Theme.smooth, value: project.artifactBytes)
                Text(parts.unit)
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            Text(localized("projects.noArtifacts", defaultValue: "No regenerable artifacts found."))
                .themeFont(.cardTitle)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    func activityLines(for project: DiscoveredProject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let edited = project.lastEditDate {
                Label(
                    localized(
                        "projects.lastEdited",
                        defaultValue: "Edited \(edited.formatted(.relative(presentation: .named)))"
                    ),
                    systemImage: "pencil"
                )
            }
            if let git = project.lastGitActivityDate {
                Label(
                    localized(
                        "projects.lastCommit",
                        defaultValue: "Git activity \(git.formatted(.relative(presentation: .named)))"
                    ),
                    systemImage: "clock.arrow.circlepath"
                )
            }
        }
        .themeFont(.caption)
        .foregroundStyle(Theme.textSecondary)
    }

    func pathChip(for project: DiscoveredProject) -> some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([project.url])
        } label: {
            HStack(spacing: 8) {
                Text((project.url.path as NSString).abbreviatingWithTildeInPath)
                    .font(Theme.mono())
                    .foregroundStyle(Color(hex: 0x8E8E95))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.forward.square")
                    .scaledFont(size: 10)
                    .foregroundStyle(Theme.textQuaternary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.radiusChip))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusChip)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusChip))
        }
        .buttonStyle(.plain)
        .help(localized("action.revealInFinder", defaultValue: "Reveal in Finder"))
    }
}
