//
//  OverviewView+Findings.swift
//  Reclaim
//
//  The overview's category grid and the "biggest single locations"
//  ranked list beneath it.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension OverviewView {
    // MARK: - Category grid

    var categoryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
            spacing: 12
        ) {
            ForEach(ToolCategory.allCases) { category in
                CategoryCard(category: category) {
                    openCategory(category)
                }
            }
        }
    }

    // MARK: - Biggest locations

    var biggestCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(localized("overview.biggestLocations", defaultValue: "Biggest single locations"))
            // Registry targets and dev-folder projects, ranked together.
            let largest = model.largestFindings(limit: 6)
            let ceiling = largest.first?.bytes ?? 0
            VStack(spacing: 0) {
                ForEach(Array(largest.enumerated()), id: \.element.id) { index, finding in
                    let fraction = ceiling > 0 ? Double(finding.bytes) / Double(ceiling) : 0
                    switch finding {
                    case .target(let target, _):
                        BiggestRow(rank: index + 1, target: target, fraction: fraction) {
                            openTarget(target)
                        }
                    case .project(let project):
                        ProjectFindingRow(rank: index + 1, project: project, fraction: fraction) {
                            openProjects()
                        }
                    }
                }
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 12)
        .padding(.horizontal, Theme.cardPadding)
        .card()
    }
}
