//
//  ProjectInspectorPanel+Artifacts.swift
//  Reclaim
//
//  The "Regenerable artifacts" list: per-artifact rows with
//  cherry-pick toggles, and the per-project "Clean just this" footer.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension ProjectInspectorPanel {
    // MARK: - Artifacts

    @ViewBuilder
    func artifactSection(for project: DiscoveredProject) -> some View {
        if !project.artifacts.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s10) {
                SectionLabel(localized(
                    "projects.artifactsSection", defaultValue: "Regenerable artifacts"
                ))
                .frame(maxWidth: .infinity, alignment: .leading)
                if project.artifacts.contains(where: { $0.measurement.bytes > 0 }) {
                    Button(projects.isProjectSelected(project)
                        ? localized("inspector.deselectAllContents", defaultValue: "Deselect all")
                        : localized("inspector.selectAllContents", defaultValue: "Select all")
                    ) {
                        projects.setProjectSelected(project, !projects.isProjectSelected(project))
                    }
                    .buttonStyle(.plain)
                    .themeFont(.miniButtonLabel)
                    .foregroundStyle(Theme.textSecondary)
                    .disabled(activity.isScanning || activity.isCleaning)
                }
            }
            .padding(.top, Theme.Space.s24)

            let peak = project.artifacts.map(\.measurement.bytes).max() ?? 1
            VStack(spacing: Theme.Space.s1) {
                ForEach(project.artifacts) { artifact in
                    artifactRow(artifact, peak: peak)
                }
            }
            .padding(.top, Theme.Space.s9)

            cherryPickFooter(for: project)
        }
    }

    private func artifactRow(_ artifact: DiscoveredArtifact, peak: Int64) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s5) {
            HStack(alignment: .center, spacing: Theme.Space.s9) {
                Toggle(
                    localized(
                        "browser.selectAccessibility",
                        defaultValue: "Select \(artifact.kind?.name ?? artifact.kindID)"
                    ),
                    isOn: Binding(
                        get: { projects.isArtifactSelected(artifact) },
                        set: { projects.setArtifactSelected(artifact, $0) }
                    )
                )
                .toggleStyle(CheckboxToggleStyle(size: 15))
                .labelsHidden()
                .disabled(!projects.isArtifactSelectable(artifact))
                .opacity(projects.isArtifactSelectable(artifact) ? 1 : 0.35)
                Text(artifact.kind?.name ?? artifact.kindID)
                    .themeFont(.meta)
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
                    .foregroundStyle(Theme.textTertiary)
            }
            MiniBar(
                fraction: peak > 0 ? Double(artifact.measurement.bytes) / Double(peak) : 0,
                color: Theme.safe
            )
            .padding(.leading, Theme.Space.s24)
        }
        .padding(.vertical, Theme.Space.s7)
    }

    /// Cherry-pick status line plus the "Clean just this" button.
    @ViewBuilder
    private func cherryPickFooter(for project: DiscoveredProject) -> some View {
        Text(pickNote(for: project))
            .themeFont(.caption)
            .foregroundStyle(Theme.textQuaternary)
            .padding(.top, Theme.Space.s9)

        Button {
            onCleanProject(project)
        } label: {
            Text(cleanLabel(for: project))
                .frame(maxWidth: .infinity)
        }
        .rcPrimary()
        .disabled(
            projects.selectedArtifacts(of: project).isEmpty
                || activity.isScanning || activity.isCleaning
        )
        .padding(.top, Theme.Space.s12)
    }

    private func scopeLabel(for project: DiscoveredProject) -> String? {
        guard let counts = projects.partialSelectionCounts(of: project) else { return nil }
        return localized(
            "format.itemsOf",
            defaultValue: "\(counts.selected) of \(counts.total) items"
        )
    }

    private func pickNote(for project: DiscoveredProject) -> String {
        guard let scope = scopeLabel(for: project) else {
            return localized("inspector.tickHint", defaultValue: "Tick items to clean only those")
        }
        let size = projects.selectedArtifactBytes(of: project).formattedBytesCompact
        return localized("inspector.tickedNote", defaultValue: "\(scope) ticked · \(size)")
    }

    private func cleanLabel(for project: DiscoveredProject) -> String {
        guard !projects.selectedArtifacts(of: project).isEmpty else {
            return localized("inspector.nothingTicked", defaultValue: "Nothing ticked here")
        }
        let size = projects.selectedArtifactBytes(of: project).formattedBytesCompact
        guard let scope = scopeLabel(for: project) else {
            return localized("inspector.cleanJustThis", defaultValue: "Clean just this · \(size)")
        }
        return localized("inspector.cleanPartial", defaultValue: "Clean \(scope) · \(size)")
    }
}
