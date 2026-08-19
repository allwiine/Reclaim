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
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                SectionLabel(localized(
                    "projects.artifactsSection", defaultValue: "Regenerable artifacts"
                ))
                .frame(maxWidth: .infinity, alignment: .leading)
                if project.artifacts.contains(where: { $0.measurement.bytes > 0 }) {
                    Button(model.projects.isProjectSelected(project)
                        ? localized("inspector.deselectAllContents", defaultValue: "Deselect all")
                        : localized("inspector.selectAllContents", defaultValue: "Select all")
                    ) {
                        model.projects.setProjectSelected(project, !model.projects.isProjectSelected(project))
                    }
                    .buttonStyle(.plain)
                    .scaledFont(size: 11, weight: .medium)
                    .foregroundStyle(Theme.textSecondary)
                    .disabled(model.activity.isScanning || model.activity.isCleaning)
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
                        get: { model.projects.isArtifactSelected(artifact) },
                        set: { model.projects.setArtifactSelected(artifact, $0) }
                    )
                )
                .toggleStyle(CheckboxToggleStyle(size: 15))
                .labelsHidden()
                .disabled(!model.projects.isArtifactSelectable(artifact))
                .opacity(model.projects.isArtifactSelectable(artifact) ? 1 : 0.35)
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
            model.projects.selectedArtifacts(of: project).isEmpty
                || model.activity.isScanning || model.activity.isCleaning
        )
        .padding(.top, 12)
    }

    private func scopeLabel(for project: DiscoveredProject) -> String? {
        guard let counts = model.projects.partialSelectionCounts(of: project) else { return nil }
        return localized(
            "format.itemsOf",
            defaultValue: "\(counts.selected) of \(counts.total) items"
        )
    }

    private func pickNote(for project: DiscoveredProject) -> String {
        guard let scope = scopeLabel(for: project) else {
            return localized("inspector.tickHint", defaultValue: "Tick items to clean only those")
        }
        let size = model.projects.selectedArtifactBytes(of: project).formattedBytesCompact
        return localized("inspector.tickedNote", defaultValue: "\(scope) ticked · \(size)")
    }

    private func cleanLabel(for project: DiscoveredProject) -> String {
        guard !model.projects.selectedArtifacts(of: project).isEmpty else {
            return localized("inspector.nothingTicked", defaultValue: "Nothing ticked here")
        }
        let size = model.projects.selectedArtifactBytes(of: project).formattedBytesCompact
        guard let scope = scopeLabel(for: project) else {
            return localized("inspector.cleanJustThis", defaultValue: "Clean just this · \(size)")
        }
        return localized("inspector.cleanPartial", defaultValue: "Clean \(scope) · \(size)")
    }
}
