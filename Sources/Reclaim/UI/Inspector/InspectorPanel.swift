//
//  InspectorPanel.swift
//  Reclaim
//
//  The browser's detail column: what a target is, what cleaning costs,
//  where the space actually sits, and — for tool-managed items — the
//  command that reclaims it.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct InspectorPanel: View {
    @Environment(TargetResultsModel.self) var results
    @Environment(SelectionModel.self) var selection
    @Environment(ActivityModel.self) var activity
    @Environment(BreakdownModel.self) var breakdowns
    let target: CleanupTarget?
    /// Opens the single-target clean confirmation ("Clean just this").
    var onCleanSingle: (CleanupTarget) -> Void = { _ in }

    @State var copied = false
    /// Expands the contents list past the top five. These live on the
    /// panel, whose identity is stable across target changes, so the
    /// `.id(target.id)` on the inner ScrollView does not reset them —
    /// the `.task(id:)` in `details(for:)` does.
    @State var showAllContents = false

    var body: some View {
        Group {
            if let target {
                details(for: target)
            } else {
                Text(localized("inspector.selectAnItem", defaultValue: "Select an item"))
                    .themeFont(.body)
                    .foregroundStyle(Theme.textQuaternary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.chromeFill)
    }

    private func details(for target: CleanupTarget) -> some View {
        let status = results.status(of: target.id)

        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s0) {
                CategoryTile(category: target.category, size: 34)

                Text(target.name)
                    .themeFont(.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, Theme.Space.s14)

                HStack(spacing: Theme.Space.s8) {
                    Badge(for: target)
                    Text(target.category.title)
                        .themeFont(.meta)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.top, Theme.Space.s8)

                sizeHeadline(status)
                    .padding(.top, Theme.Space.s16)

                Text(target.summary)
                    .themeFont(.body)
                    .lineSpacing(3.5)
                    .foregroundStyle(Theme.textParagraph)
                    .padding(.top, Theme.Space.s14)

                if let note = target.note {
                    Label(note, systemImage: "info.circle")
                        .themeFont(.caption)
                        .lineSpacing(2.5)
                        .foregroundStyle(
                            target.safety == .safe ? Theme.textTertiary : Theme.cautionTitle
                        )
                        .padding(.top, Theme.Space.s10)
                }

                if target.strategy.isCleanable, selection.isExcludedFromAutoSelect(target) {
                    Label(
                        localized(
                            "inspector.excludedNote",
                            defaultValue: "Kept out of automatic selection — tick it manually to clean it."
                        ),
                        systemImage: "hand.raised"
                    )
                    .themeFont(.caption)
                    .lineSpacing(2.5)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, Theme.Space.s10)
                }

                pathChip(for: target, status: status)
                    .padding(.top, Theme.Space.s14)

                if !target.strategy.isCleanable {
                    delegatedCard(for: target)
                        .padding(.top, Theme.Space.s16)
                }

                if case .command(let spec) = target.strategy {
                    commandInfo(spec)
                        .padding(.top, Theme.Space.s14)
                }

                breakdown(for: target, status: status)

                footer(status)
                    .padding(.top, Theme.Space.s18)
            }
            .padding(.horizontal, Theme.Space.s20)
            .padding(.top, Theme.Space.s18)
            .padding(.bottom, Theme.Space.s24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(target.id)
        .task(id: target.id) {
            // Reset per-target view state that lives on the (stable) panel.
            showAllContents = false
            copied = false
            breakdowns.load(for: target)
        }
    }

}

// MARK: - Previews

#if DEBUG
#Preview("Measured", traits: .fixedLayout(width: 336, height: 810)) {
    let model = PreviewData.scanned()
    return InspectorPanel(target: model.results.targets.first { $0.id == "xcode-derived-data" })
        .background(Theme.background)
        .appEnvironment(model)
        .preferredColorScheme(.dark)
}

#Preview("Tool-managed", traits: .fixedLayout(width: 336, height: 810)) {
    let model = PreviewData.scanned()
    return InspectorPanel(target: model.results.targets.first { $0.id == "docker-vm-disk" })
        .background(Theme.background)
        .appEnvironment(model)
        .preferredColorScheme(.dark)
}
#endif
