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
    @Environment(AppModel.self) var model
    let scope: ConfirmScope
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var appeared = false

    /// The one target of a "Clean just this" confirmation, if that is
    /// what this sheet covers.
    var singleTarget: CleanupTarget? {
        guard case .single(let id) = scope else { return nil }
        return model.results.targets.first { $0.id == id }
    }

    /// The one project of a per-project confirmation, if that is what
    /// this sheet covers.
    var singleProject: DiscoveredProject? {
        guard case .project(let id) = scope else { return nil }
        return model.projects.discovered.first { $0.id == id }
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
            else { singleTarget.map { [$0] } ?? model.selection.selectedTargets }
        let toTrash = model.settings.disposal == .trash

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
