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
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var appeared = false

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
        let picked = model.selectedTargets
        let toTrash = model.disposal == .trash

        return VStack(alignment: .leading, spacing: 0) {
            Text(title(picked))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 24)
                .padding(.top, 22)

            Text(bodyText(toTrash: toTrash))
                .font(Theme.body)
                .lineSpacing(3.5)
                .foregroundStyle(Color(hex: 0xA8A8AF))
                .padding(.horizontal, 24)
                .padding(.top, 7)
                .contentTransition(.opacity)
                .animation(Theme.quick, value: toTrash)

            itemList(picked)
                .padding(.horizontal, 24)
                .padding(.top, 16)

            if let warning = warningText(picked) {
                Text(warning)
                    .font(.system(size: 12))
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
                Button("Cancel", action: onCancel)
                    .buttonStyle(.rcSecondary)
                    .keyboardShortcut(.cancelAction)
                if toTrash {
                    Button("Move to Trash", action: onConfirm)
                        .buttonStyle(.rcPrimary)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Delete Permanently", action: onConfirm)
                        .buttonStyle(.rcDanger)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.radiusTile))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusTile)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.6), radius: 35, y: 20)
    }

    // MARK: - Content

    private func title(_ picked: [CleanupTarget]) -> String {
        let prefix = model.dryRun ? "Dry run: reclaim" : "Reclaim"
        let locations = "\(picked.count) location\(picked.count == 1 ? "" : "s")"
        return "\(prefix) \(model.selectedBytes.formattedBytesCompact) from \(locations)?"
    }

    private func bodyText(toTrash: Bool) -> String {
        if model.dryRun {
            return "Dry run is on — Reclaim will only report what would be removed. Nothing is touched."
        }
        return toTrash
            ? "Everything listed below moves to the Trash. Nothing is removed permanently until you empty it."
            : "Everything listed below is deleted immediately and cannot be recovered."
    }

    private func itemList(_ picked: [CleanupTarget]) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(picked) { target in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(BadgeKind(for: target).color)
                            .frame(width: 7, height: 7)
                        Text(target.name)
                            .font(Theme.body)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(sizeLabel(for: target))
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(Color(hex: 0x8E8E95))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .overlay(alignment: .bottom) {
                        if target.id != picked.last?.id {
                            Rectangle().fill(Theme.separator).frame(height: 1)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 210)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: Theme.radiusInset))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusInset)
                .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
        }
    }

    private func sizeLabel(for target: CleanupTarget) -> String {
        if case .unmeasurable = model.status(of: target.id) { return "size unknown" }
        return model.bytes(of: target).formattedBytesCompact
    }

    private func warningText(_ picked: [CleanupTarget]) -> String? {
        var lines: [String] = []
        if picked.contains(where: { $0.safety == .destructive }) {
            lines.append("This selection includes items marked Destructive — things you created, like emulators, that cannot be restored.")
        } else if picked.contains(where: { $0.safety == .caution }) {
            lines.append("This selection includes items marked Caution. They can be restored, but re-downloading models or losing history costs something.")
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
            Text("Move to Trash instead of deleting")
                .font(Theme.body)
                .foregroundStyle(Color(hex: 0xC8C8CF))
        }
        .toggleStyle(SmallCheckToggleStyle())
        .help("The app-wide disposal setting — also in Settings")
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
                            .font(.system(size: 8.5, weight: .bold))
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
    ConfirmSheet(onCancel: {}, onConfirm: {})
        .background(Theme.background)
        .environment(PreviewData.scanned())
        .preferredColorScheme(.dark)
}
#endif
