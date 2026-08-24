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
    /// Kept for `selectedBytes` only — a cross-model member.
    @Environment(AppModel.self) var model
    @Environment(SettingsStore.self) var settings
    @Environment(TargetResultsModel.self) var results
    @Environment(ProjectsModel.self) var projects
    @Environment(SelectionModel.self) var selection
    let scope: ConfirmScope
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var appeared = false

    /// The one target of a "Clean just this" confirmation, if that is
    /// what this sheet covers.
    var singleTarget: CleanupTarget? {
        guard case .single(let id) = scope else { return nil }
        return results.targets.first { $0.id == id }
    }

    /// The one project of a per-project confirmation, if that is what
    /// this sheet covers.
    var singleProject: DiscoveredProject? {
        guard case .project(let id) = scope else { return nil }
        return projects.discovered.first { $0.id == id }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Dimmed, blurred backdrop; clicking it cancels.
            Theme.sheetScrim
                .background(.ultraThinMaterial.opacity(0.4))
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            panel
                .frame(width: 470)
                .padding(.top, Theme.Space.s46)
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
            else { singleTarget.map { [$0] } ?? selection.selectedTargets }
        let toTrash = settings.disposal == .trash

        return VStack(alignment: .leading, spacing: Theme.Space.s0) {
            Text(title(picked))
                .themeFont(.sheetTitle)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Space.s24)
                .padding(.top, Theme.Space.s22)

            Text(bodyText(toTrash: toTrash))
                .themeFont(.body)
                .lineSpacing(3.5)
                .foregroundStyle(Theme.textParagraph)
                .padding(.horizontal, Theme.Space.s24)
                .padding(.top, Theme.Space.s7)
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
            .padding(.horizontal, Theme.Space.s24)
            .padding(.top, Theme.Space.s16)

            if let warning = warningText(picked) {
                Text(warning)
                    .themeFont(.meta)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.textDangerBanner)
                    .padding(Theme.Space.s12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Theme.dangerWarn.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: Theme.radiusInset)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.radiusInset)
                            .strokeBorder(Theme.dangerWarn.opacity(0.35), lineWidth: 0.5)
                    }
                    .padding(.horizontal, Theme.Space.s24)
                    .padding(.top, Theme.Space.s14)
            }

            HStack(spacing: Theme.Space.s10) {
                trashToggle(toTrash: toTrash)
                Spacer()
                Button(localized("action.cancel", defaultValue: "Cancel"), action: onCancel)
                    .rcSecondary()
                    .keyboardShortcut(.cancelAction)
                if toTrash {
                    Button(localized("confirm.moveToTrash", defaultValue: "Move to Trash"), action: onConfirm)
                        .rcPrimary()
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(localized("confirm.deletePermanently", defaultValue: "Delete Permanently"), action: onConfirm)
                        .rcDanger()
                }
            }
            .padding(.horizontal, Theme.Space.s24)
            .padding(.top, Theme.Space.s18)
            .padding(.bottom, Theme.Space.s20)
        }
        // Liquid Glass on Tahoe (a floating sheet is the canonical glass
        // surface); the solid raised fill on earlier systems.
        .floatingSurface(cornerRadius: Theme.radiusTile)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusTile)
                .strokeBorder(Theme.borderFloating, lineWidth: 0.5)
        }
        .shadow(color: Theme.sheetShadow, radius: 35, y: 20)
    }

}

// MARK: - Previews

#if DEBUG
#Preview(traits: .fixedLayout(width: 1320, height: 856)) {
    ConfirmSheet(scope: .selection, onCancel: {}, onConfirm: {})
        .background(Theme.background)
        .appEnvironment(PreviewData.scanned())
        .preferredColorScheme(.dark)
}
#endif
