//
//  TargetRow.swift
//  Reclaim
//
//  One cleanup target in a category list: selection checkbox, name,
//  safety badge, description, notes, and live scan status.
//

import AppKit
import ReclaimKit
import SwiftUI

struct TargetRow: View {
    @Environment(AppModel.self) private var model
    let target: CleanupTarget

    private var status: TargetStatus { model.status(of: target.id) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            checkbox
            description
            Spacer(minLength: 12)
            StatusLabel(status: status)
        }
        .padding(.vertical, 6)
        .contextMenu { contextMenu }
    }

    // MARK: - Pieces

    private var checkbox: some View {
        Toggle(
            "Select \(target.name)",
            isOn: Binding(
                get: { model.isSelected(target) },
                set: { model.setSelected(target, $0) }
            )
        )
        .toggleStyle(.checkbox)
        .labelsHidden()
        .disabled(!model.isSelectable(target))
        .padding(.top, 1)
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(target.name)
                    .fontWeight(.medium)
                SafetyBadge(level: target.safety)
            }

            Text(target.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let note = target.note {
                Label(note, systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(target.safety == .safe ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .manual(let instructions) = target.strategy {
                Label(instructions, systemImage: "hand.raised")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .command(let spec) = target.strategy {
                Label("Runs `\(spec.displayCommand)`", systemImage: "terminal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        let paths = status.resolvedPaths
        if let first = paths.first {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([first])
            }
            Button("Copy Path\(paths.count > 1 ? "s" : "")") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    paths.map(\.path).joined(separator: "\n"),
                    forType: .string
                )
            }
        }
    }
}
