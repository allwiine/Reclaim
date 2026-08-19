//
//  ConfirmSheet+Lists.swift
//  Reclaim
//
//  The scrollable list card in three flavors: the full multi-target
//  selection, a single target's cherry-picked paths, and a single
//  project's cherry-picked artifacts.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension ConfirmSheet {
    func itemList(_ picked: [CleanupTarget]) -> some View {
        listCard {
            ForEach(picked) { target in
                HStack(spacing: 10) {
                    Circle()
                        .fill(BadgeKind(for: target).color)
                        .frame(width: 7, height: 7)
                    Text(target.name)
                        .themeFont(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let scope = partialScopeLabel(for: target) {
                        Text(scope)
                            .themeFont(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(sizeLabel(for: target))
                        .scaledFont(size: 12)
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: 0x8E8E95))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) {
                    if target.id != picked.last?.id || !model.projects.selectedArtifacts.isEmpty {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }
                }
            }
            ForEach(model.projects.selectedArtifacts) { artifact in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Theme.safe)
                        .frame(width: 7, height: 7)
                    Text(artifactLabel(artifact))
                        .themeFont(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(artifact.measurement.bytes.formattedBytesCompact)
                        .scaledFont(size: 12)
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: 0x8E8E95))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) {
                    if artifact.id != model.projects.selectedArtifacts.last?.id {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }
                }
            }
        }
    }

    private func artifactLabel(_ artifact: DiscoveredArtifact) -> String {
        let projectName = model.projects.discovered
            .first { $0.artifacts.contains(where: { $0.id == artifact.id }) }?
            .name ?? ""
        return model.projects.artifactDisplayName(kindID: artifact.kindID, projectName: projectName)
    }

    /// "Clean just this": the exact scan-time items that will go.
    func singlePathList(for target: CleanupTarget) -> some View {
        let paths = model.selection.selectedCleanupPaths(of: target)
        return listCard {
            ForEach(paths, id: \.path) { url in
                HStack(spacing: 10) {
                    Circle()
                        .fill(BadgeKind(for: target).color)
                        .frame(width: 7, height: 7)
                    Text(url.lastPathComponent)
                        .themeFont(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(model.selection.breakdownBytes(of: target, path: url.path)
                        .map(\.formattedBytesCompact)
                        ?? localized("confirm.sizeUnknown", defaultValue: "size unknown"))
                        .scaledFont(size: 12)
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: 0x8E8E95))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) {
                    if url.path != paths.last?.path {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }
                }
            }
        }
    }

    /// Per-project "Clean just this": the ticked artifacts that will go.
    func projectArtifactList(for project: DiscoveredProject) -> some View {
        let picked = model.projects.selectedArtifacts(of: project)
        return listCard {
            ForEach(picked) { artifact in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Theme.safe)
                        .frame(width: 7, height: 7)
                    Text(artifact.kind?.name ?? artifact.kindID)
                        .themeFont(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(artifact.url.lastPathComponent)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textQuaternary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(artifact.measurement.bytes.formattedBytesCompact)
                        .scaledFont(size: 12)
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: 0x8E8E95))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) {
                    if artifact.id != picked.last?.id {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }
                }
            }
        }
    }

    private func listCard(@ViewBuilder rows: () -> some View) -> some View {
        ScrollView {
            VStack(spacing: 0, content: rows)
        }
        .frame(maxHeight: 210)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: Theme.radiusInset))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusInset)
                .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
        }
    }

    private func partialScopeLabel(for target: CleanupTarget) -> String? {
        guard let counts = model.selection.partialSelectionCounts(of: target) else { return nil }
        return localized(
            "format.itemsOf",
            defaultValue: "\(counts.selected) of \(counts.total) items"
        )
    }

    private func sizeLabel(for target: CleanupTarget) -> String {
        if case .unmeasurable = model.results.status(of: target.id) {
            return localized("confirm.sizeUnknown", defaultValue: "size unknown")
        }
        return model.selection.selectedBytes(of: target).formattedBytesCompact
    }
}
