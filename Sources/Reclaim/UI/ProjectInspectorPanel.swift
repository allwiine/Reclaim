//
//  ProjectInspectorPanel.swift
//  Reclaim
//
//  The projects screen's detail column: what a project is, when it
//  was last touched, and its regenerable artifacts with per-artifact
//  cherry-picking and a per-project clean action.
//

import AppKit
import ReclaimAppCore
import ReclaimKit
import SwiftUI

/// "No recent activity" capsule shared by the project row and this panel.
struct StaleBadge: View {
    var body: some View {
        Text(localized("projects.staleBadge", defaultValue: "No recent activity"))
            .themeFont(.caption)
            .foregroundStyle(Theme.cautionTitle)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.cautionTitle.opacity(0.12), in: Capsule())
    }
}

struct ProjectInspectorPanel: View {
    @Environment(AppModel.self) private var model
    let project: DiscoveredProject?
    /// Opens the per-project clean confirmation ("Clean just this").
    var onCleanProject: (DiscoveredProject) -> Void = { _ in }

    var body: some View {
        Group {
            if let project {
                details(for: project)
            } else {
                Text(localized("projects.selectProject", defaultValue: "Select a project"))
                    .themeFont(.body)
                    .foregroundStyle(Theme.textQuaternary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.white.opacity(0.02))
    }

    private func details(for project: DiscoveredProject) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                projectTile

                Text(project.name)
                    .scaledFont(size: 17, weight: .bold)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 14)

                HStack(spacing: 8) {
                    if model.isProjectStale(project) {
                        StaleBadge()
                    }
                    Text((project.devRoot.path as NSString).abbreviatingWithTildeInPath)
                        .scaledFont(size: 12)
                        .foregroundStyle(Color(hex: 0x8E8E95))
                        .lineLimit(1)
                }
                .padding(.top, 8)

                sizeHeadline(for: project)
                    .padding(.top, 16)

                activityLines(for: project)
                    .padding(.top, 14)

                pathChip(for: project)
                    .padding(.top, 14)

                artifactSection(for: project)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(project.id)
    }

    // MARK: - Pieces

    private var projectTile: some View {
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
    private func sizeHeadline(for project: DiscoveredProject) -> some View {
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
    private func activityLines(for project: DiscoveredProject) -> some View {
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

    private func pathChip(for project: DiscoveredProject) -> some View {
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

    // MARK: - Artifacts

    @ViewBuilder
    private func artifactSection(for project: DiscoveredProject) -> some View {
        if !project.artifacts.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                SectionLabel(localized(
                    "projects.artifactsSection", defaultValue: "Regenerable artifacts"
                ))
                .frame(maxWidth: .infinity, alignment: .leading)
                if project.artifacts.contains(where: { $0.measurement.bytes > 0 }) {
                    Button(model.isProjectSelected(project)
                        ? localized("inspector.deselectAllContents", defaultValue: "Deselect all")
                        : localized("inspector.selectAllContents", defaultValue: "Select all")
                    ) {
                        model.setProjectSelected(project, !model.isProjectSelected(project))
                    }
                    .buttonStyle(.plain)
                    .scaledFont(size: 11, weight: .medium)
                    .foregroundStyle(Theme.textSecondary)
                    .disabled(model.isScanning || model.isCleaning)
                }
            }
            .padding(.top, 24)

            let peak = project.artifacts.map(\.measurement.bytes).max() ?? 1
            VStack(spacing: 1) {
                ForEach(project.artifacts) { artifact in
                    artifactRow(artifact, peak: peak)
                }
            }
            .padding(.top, 9)

            cherryPickFooter(for: project)
        }
    }

    private func artifactRow(_ artifact: DiscoveredArtifact, peak: Int64) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 9) {
                Toggle(
                    localized(
                        "browser.selectAccessibility",
                        defaultValue: "Select \(artifact.kind?.name ?? artifact.kindID)"
                    ),
                    isOn: Binding(
                        get: { model.isArtifactSelected(artifact) },
                        set: { model.setArtifactSelected(artifact, $0) }
                    )
                )
                .toggleStyle(CheckboxToggleStyle(size: 15))
                .labelsHidden()
                .disabled(!model.isArtifactSelectable(artifact))
                .opacity(model.isArtifactSelectable(artifact) ? 1 : 0.35)
                Text(artifact.kind?.name ?? artifact.kindID)
                    .scaledFont(size: 12)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(artifact.url.lastPathComponent)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textQuaternary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(artifact.measurement.bytes.formattedBytesCompact)
                    .themeFont(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: 0x8E8E95))
            }
            MiniBar(
                fraction: peak > 0 ? Double(artifact.measurement.bytes) / Double(peak) : 0,
                color: Theme.safe
            )
            .padding(.leading, 24)
        }
        .padding(.vertical, 7)
    }

    /// Cherry-pick status line plus the "Clean just this" button.
    @ViewBuilder
    private func cherryPickFooter(for project: DiscoveredProject) -> some View {
        Text(pickNote(for: project))
            .themeFont(.caption)
            .foregroundStyle(Theme.textQuaternary)
            .padding(.top, 9)

        Button {
            onCleanProject(project)
        } label: {
            Text(cleanLabel(for: project))
                .frame(maxWidth: .infinity)
        }
        .rcPrimary()
        .disabled(
            model.selectedArtifacts(of: project).isEmpty
                || model.isScanning || model.isCleaning
        )
        .padding(.top, 12)
    }

    private func scopeLabel(for project: DiscoveredProject) -> String? {
        guard let counts = model.partialSelectionCounts(of: project) else { return nil }
        return localized(
            "format.itemsOf",
            defaultValue: "\(counts.selected) of \(counts.total) items"
        )
    }

    private func pickNote(for project: DiscoveredProject) -> String {
        guard let scope = scopeLabel(for: project) else {
            return localized("inspector.tickHint", defaultValue: "Tick items to clean only those")
        }
        let size = model.selectedArtifactBytes(of: project).formattedBytesCompact
        return localized("inspector.tickedNote", defaultValue: "\(scope) ticked · \(size)")
    }

    private func cleanLabel(for project: DiscoveredProject) -> String {
        guard !model.selectedArtifacts(of: project).isEmpty else {
            return localized("inspector.nothingTicked", defaultValue: "Nothing ticked here")
        }
        let size = model.selectedArtifactBytes(of: project).formattedBytesCompact
        guard let scope = scopeLabel(for: project) else {
            return localized("inspector.cleanJustThis", defaultValue: "Clean just this · \(size)")
        }
        return localized("inspector.cleanPartial", defaultValue: "Clean \(scope) · \(size)")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Project", traits: .fixedLayout(width: 336, height: 810)) {
    let model = PreviewData.scannedWithProjects()
    return ProjectInspectorPanel(project: model.projects.first)
        .background(Theme.background)
        .environment(model)
        .preferredColorScheme(.dark)
}

#Preview("No artifacts", traits: .fixedLayout(width: 336, height: 810)) {
    let model = PreviewData.scannedWithProjects()
    return ProjectInspectorPanel(project: model.projects.last)
        .background(Theme.background)
        .environment(model)
        .preferredColorScheme(.dark)
}
#endif
