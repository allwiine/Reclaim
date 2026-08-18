//
//  ConfirmSheet.swift
//  Reclaim
//
//  The pre-clean confirmation: exactly what will be disposed of, how,
//  the warnings that matter (risky items, running apps), and the
//  per-pass Trash choice. Nothing is cleaned without passing here.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct ConfirmSheet: View {
    @Environment(AppModel.self) private var model
    let scope: ConfirmScope
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var appeared = false

    /// The one target of a "Clean just this" confirmation, if that is
    /// what this sheet covers.
    private var singleTarget: CleanupTarget? {
        guard case .single(let id) = scope else { return nil }
        return model.targets.first { $0.id == id }
    }

    /// The one project of a per-project confirmation, if that is what
    /// this sheet covers.
    private var singleProject: DiscoveredProject? {
        guard case .project(let id) = scope else { return nil }
        return model.projects.first { $0.id == id }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Dimmed, blurred backdrop; clicking it cancels.
            Color.black.opacity(0.42)
                .background(.ultraThinMaterial.opacity(0.4))
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            panel
                .frame(width: 470)
                .padding(.top, 46)
                .scaleEffect(appeared ? 1 : 0.96, anchor: .top)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { appeared = true }
        }
    }

    // MARK: - Panel

    private var panel: some View {
        let picked: [CleanupTarget] =
            if case .project = scope { [] }
            else { singleTarget.map { [$0] } ?? model.selectedTargets }
        let toTrash = model.disposal == .trash

        return VStack(alignment: .leading, spacing: 0) {
            Text(title(picked))
                .scaledFont(size: 15, weight: .bold)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 24)
                .padding(.top, 22)

            Text(bodyText(toTrash: toTrash))
                .themeFont(.body)
                .lineSpacing(3.5)
                .foregroundStyle(Color(hex: 0xA8A8AF))
                .padding(.horizontal, 24)
                .padding(.top, 7)
                .contentTransition(.opacity)
                .animation(Theme.quick, value: toTrash)

            Group {
                if let target = singleTarget {
                    singlePathList(for: target)
                } else if let project = singleProject {
                    projectArtifactList(for: project)
                } else {
                    itemList(picked)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            if let warning = warningText(picked) {
                Text(warning)
                    .scaledFont(size: 12)
                    .lineSpacing(3)
                    .foregroundStyle(Color(hex: 0xE8C9C6))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Theme.dangerWarn.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: Theme.radiusInset)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.radiusInset)
                            .strokeBorder(Theme.dangerWarn.opacity(0.35), lineWidth: 0.5)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
            }

            HStack(spacing: 10) {
                trashToggle(toTrash: toTrash)
                Spacer()
                Button(localized("action.cancel", defaultValue: "Cancel"), action: onCancel)
                    .buttonStyle(.rcSecondary)
                    .keyboardShortcut(.cancelAction)
                if toTrash {
                    Button(localized("confirm.moveToTrash", defaultValue: "Move to Trash"), action: onConfirm)
                        .buttonStyle(.rcPrimary)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(localized("confirm.deletePermanently", defaultValue: "Delete Permanently"), action: onConfirm)
                        .buttonStyle(.rcDanger)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        // Liquid Glass on Tahoe (a floating sheet is the canonical glass
        // surface); the solid raised fill on earlier systems.
        .floatingSurface(cornerRadius: Theme.radiusTile)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusTile)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.6), radius: 35, y: 20)
    }

    // MARK: - Content

    private func title(_ picked: [CleanupTarget]) -> String {
        if let target = singleTarget {
            let space = model.selectedBytes(of: target).formattedBytesCompact
            if let counts = model.partialSelectionCounts(of: target) {
                let scope = localized(
                    "format.itemsOf",
                    defaultValue: "\(counts.selected) of \(counts.total) items"
                )
                return localized(
                    "confirm.titleSinglePartial",
                    defaultValue: "Reclaim \(space) from \(scope) in \(target.name)?"
                )
            }
            return localized(
                "confirm.titleSingle",
                defaultValue: "Reclaim \(space) from \(target.name)?"
            )
        }
        if let project = singleProject {
            let space = model.selectedArtifactBytes(of: project).formattedBytesCompact
            if let counts = model.partialSelectionCounts(of: project) {
                let scope = localized(
                    "format.itemsOf",
                    defaultValue: "\(counts.selected) of \(counts.total) items"
                )
                return localized(
                    "confirm.titleSinglePartial",
                    defaultValue: "Reclaim \(space) from \(scope) in \(project.name)?"
                )
            }
            return localized(
                "confirm.titleSingle",
                defaultValue: "Reclaim \(space) from \(project.name)?"
            )
        }
        let space = model.selectedBytes.formattedBytesCompact
        let locationCount = picked.count + model.selectedArtifacts.count
        return model.dryRun
            ? localized(
                "confirm.titleDryRun",
                defaultValue: "Dry run: reclaim \(space) from \(locationCount) locations?"
            )
            : localized(
                "confirm.title",
                defaultValue: "Reclaim \(space) from \(locationCount) locations?"
            )
    }

    private func bodyText(toTrash: Bool) -> String {
        if model.dryRun {
            return localized(
                "confirm.bodyDryRun",
                defaultValue: "Dry run is on — Reclaim will only report what would be removed. Nothing is touched."
            )
        }
        if let target = singleTarget {
            if model.isPartiallySelected(target) {
                return localized(
                    "confirm.bodySinglePartial",
                    defaultValue: "Only the items listed below are affected. The rest of \(target.name) stays where it is."
                )
            }
            return toTrash
                ? localized(
                    "confirm.bodySingleTrash",
                    defaultValue: "This one location moves to the Trash. Nothing else in your selection is touched."
                )
                : localized(
                    "confirm.bodySingleDelete",
                    defaultValue: "This one location is deleted immediately and cannot be recovered."
                )
        }
        if let project = singleProject, model.isProjectPartiallySelected(project) {
            return localized(
                "confirm.bodySinglePartial",
                defaultValue: "Only the items listed below are affected. The rest of \(project.name) stays where it is."
            )
        }
        return toTrash
            ? localized(
                "confirm.bodyTrash",
                defaultValue: "Everything listed below moves to the Trash. Nothing is removed permanently until you empty it."
            )
            : localized(
                "confirm.bodyDelete",
                defaultValue: "Everything listed below is deleted immediately and cannot be recovered."
            )
    }

    private func itemList(_ picked: [CleanupTarget]) -> some View {
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
                    if target.id != picked.last?.id || !model.selectedArtifacts.isEmpty {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }
                }
            }
            ForEach(model.selectedArtifacts) { artifact in
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
                    if artifact.id != model.selectedArtifacts.last?.id {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }
                }
            }
        }
    }

    private func artifactLabel(_ artifact: DiscoveredArtifact) -> String {
        let projectName = model.projects
            .first { $0.artifacts.contains(where: { $0.id == artifact.id }) }?
            .name ?? ""
        return model.artifactDisplayName(kindID: artifact.kindID, projectName: projectName)
    }

    /// "Clean just this": the exact scan-time items that will go.
    private func singlePathList(for target: CleanupTarget) -> some View {
        let paths = model.selectedCleanupPaths(of: target)
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
                    Text(model.breakdownBytes(of: target, path: url.path)
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
    private func projectArtifactList(for project: DiscoveredProject) -> some View {
        let picked = model.selectedArtifacts(of: project)
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
        guard let counts = model.partialSelectionCounts(of: target) else { return nil }
        return localized(
            "format.itemsOf",
            defaultValue: "\(counts.selected) of \(counts.total) items"
        )
    }

    private func sizeLabel(for target: CleanupTarget) -> String {
        if case .unmeasurable = model.status(of: target.id) {
            return localized("confirm.sizeUnknown", defaultValue: "size unknown")
        }
        return model.selectedBytes(of: target).formattedBytesCompact
    }

    private func warningText(_ picked: [CleanupTarget]) -> String? {
        var lines: [String] = []
        if picked.contains(where: { $0.safety == .destructive }) {
            lines.append(localized(
                "confirm.destructiveWarning",
                defaultValue: "This selection includes items marked Destructive — things you created, like emulators, that cannot be restored."
            ))
        } else if picked.contains(where: { $0.safety == .caution }) {
            lines.append(localized(
                "confirm.cautionWarning",
                defaultValue: "This selection includes items marked Caution. They can be restored, but re-downloading models or losing history costs something."
            ))
        }
        if let running = RunningTools.warning(for: picked) {
            lines.append(running)
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }

    private func trashToggle(toTrash: Bool) -> some View {
        @Bindable var model = model
        return Toggle(isOn: Binding(
            get: { model.disposal == .trash },
            set: { model.disposal = $0 ? .trash : .delete }
        )) {
            Text(localized("confirm.trashToggle", defaultValue: "Move to Trash instead of deleting"))
                .themeFont(.body)
                .foregroundStyle(Color(hex: 0xC8C8CF))
        }
        .toggleStyle(SmallCheckToggleStyle())
        .help(localized(
            "confirm.trashToggleHelp",
            defaultValue: "The app-wide disposal setting — also in Settings"
        ))
    }
}

/// 16-pt checkbox with a trailing label, used in the sheet footer.
private struct SmallCheckToggleStyle: ToggleStyle {
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

// MARK: - Previews

#if DEBUG
#Preview(traits: .fixedLayout(width: 1320, height: 856)) {
    ConfirmSheet(scope: .selection, onCancel: {}, onConfirm: {})
        .background(Theme.background)
        .environment(PreviewData.scanned())
        .preferredColorScheme(.dark)
}
#endif
