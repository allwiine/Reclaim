//
//  OverviewView+Reclaimable.swift
//  Reclaim
//
//  The overview's headline card: the reclaimable ring and the
//  safe/review/project-artifact breakdown beneath it.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension OverviewView {
    // MARK: - Reclaimable card

    var reclaimableCard: some View {
        HStack(spacing: 22) {
            ring

            VStack(alignment: .leading, spacing: 0) {
                // "Found", not "reclaimable": the ring's total includes
                // tool-managed items Reclaim measures but never deletes.
                SectionLabel(localized("overview.foundOnThisMac", defaultValue: "Found on this Mac"))

                VStack(alignment: .leading, spacing: 9) {
                    // After a clean pass the safe bucket is often empty;
                    // saying so beats formatting 0 bytes as "< 1 MB" and
                    // offering a button that cannot do anything.
                    if results.safeReclaimableBytes > 0 {
                        breakdownRow(
                            color: Theme.safe,
                            title: localized(
                                "overview.safeToRemove",
                                defaultValue: "\(results.safeReclaimableBytes.formattedBytesCompact) safe to remove"
                            ),
                            subtitle: localized(
                                "overview.safeItemsSubtitle",
                                defaultValue: "\(results.safeReclaimableCount) safe items, regenerated automatically"
                            )
                        )
                    } else {
                        breakdownRow(
                            color: Theme.safe,
                            title: localized(
                                "overview.nothingSafeLeft",
                                defaultValue: "Nothing safe left to remove"
                            ),
                            subtitle: localized(
                                "overview.nothingSafeLeftSubtitle",
                                defaultValue: "Everything rated Safe is already clean — scan again to re-measure."
                            )
                        )
                    }
                    breakdownRow(
                        color: Theme.cautionBright,
                        title: localized(
                            "overview.needsDecision",
                            defaultValue: "\(results.reviewBytes.formattedBytesCompact) needs a decision"
                        ),
                        subtitle: localized(
                            "overview.reviewItemsSubtitle",
                            defaultValue: "\(results.reviewCount) items worth a look first"
                        )
                    )
                    // Dev-folder artifacts are inside the ring's total, so
                    // the rows only sum up to it with this third slice.
                    if projects.projectArtifactBytes > 0 {
                        breakdownRow(
                            color: Theme.accent,
                            title: localized(
                                "overview.projectArtifacts",
                                defaultValue: "\(projects.projectArtifactBytes.formattedBytesCompact) in project artifacts"
                            ),
                            subtitle: localized(
                                "overview.projectArtifactsSubtitle",
                                defaultValue: "\(projects.projectsWithArtifactsCount) projects, cleaned from the Projects screen"
                            )
                        )
                    }
                }
                .padding(.top, 13)

                HStack(spacing: 9) {
                    if results.safeReclaimableBytes > 0 {
                        Button(
                            localized("overview.reclaimSafeButton", defaultValue: "Reclaim safe space"),
                            action: reclaimSafe
                        )
                        .rcPrimary()
                    } else {
                        Button(localized("action.scanAgain", defaultValue: "Scan again")) {
                            scanner.scanAll()
                        }
                        .rcPrimary()
                    }
                    Button(localized("overview.reviewEverythingButton", defaultValue: "Review everything")) {
                        reviewEverything()
                    }
                    .rcSecondary()
                }
                .padding(.top, 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.cardPadding)
        .card()
    }

    private var ring: some View {
        SegmentedRing(segments: ringSegments)
            .frame(width: 136, height: 136)
            .overlay {
                VStack(spacing: 1) {
                    Text(model.totalFoundBytes.byteParts.value)
                        .font(Theme.heroNumber(25))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                        .animation(Theme.smooth, value: model.totalFoundBytes)
                    Text(model.totalFoundBytes.byteParts.unit)
                        .scaledFont(size: 10.5, weight: .semibold)
                        .tracking(0.7)
                        .foregroundStyle(Theme.textLabel)
                }
            }
    }

    // The center number is `totalFoundBytes`, which counts dev-folder
    // artifacts — the colored composition must cover the same total,
    // so projects get their own segment.
    private var ringSegments: [MeterSegment] {
        let totals = results.categoryTotals()
        let projectBytes = projects.projectArtifactBytes
        let sum = max(1, totals.reduce(Int64(0)) { $0 + $1.bytes } + projectBytes)
        var segments = totals.map {
            MeterSegment(
                id: $0.category.id,
                fraction: Double($0.bytes) / Double(sum),
                color: $0.category.color
            )
        }
        if projectBytes > 0 {
            segments.append(MeterSegment(
                id: "projects",
                fraction: Double(projectBytes) / Double(sum),
                color: Theme.accent
            ))
        }
        return segments
    }

    private func breakdownRow(color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .themeFont(.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(Theme.smooth, value: title)
                Text(subtitle)
                    .themeFont(.footnote)
                    .foregroundStyle(Theme.textLabel)
            }
        }
    }
}
