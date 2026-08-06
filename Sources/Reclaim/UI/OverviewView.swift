//
//  OverviewView.swift
//  Reclaim
//
//  The dashboard: headline numbers, a per-category chart, and the
//  largest individual items. Before the first scan it shows a call to
//  action instead.
//

import AppKit
import Charts
import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    /// Navigates the split view to a category when a chart row or
    /// "largest item" row is clicked.
    let openCategory: (ToolCategory) -> Void

    var body: some View {
        if model.lastScan == nil && !model.isScanning {
            emptyState
        } else {
            content
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No scan yet", systemImage: "internaldrive")
        } description: {
            Text("Scan this Mac to see how much space Xcode, Android Studio, Claude Code and other developer tools are holding on to.")
        } actions: {
            Button("Scan Now") { model.scanAll() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Dashboard

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if model.hasFullDiskAccess == false {
                    fullDiskAccessBanner
                }
                if model.lastScan != nil, !model.lastScanWasComplete, !model.isScanning {
                    partialScanNotice
                }
                statCards
                chartSection
                largestSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationSubtitle("Overview")
    }

    /// Shown when the process cannot read TCC-protected locations, so
    /// "Empty" rows are never silently caused by missing permissions.
    private var fullDiskAccessBanner: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full Disk Access is not granted")
                        .fontWeight(.medium)
                    Text("Some locations cannot be measured or cleaned, so results may be incomplete.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Privacy Settings…") {
                    NSWorkspace.shared.open(PrivacyLinks.fullDiskAccess)
                }
            }
            .padding(4)
        }
    }

    /// Shown when the last scan was stopped early, so partial totals
    /// are never mistaken for a full picture.
    private var partialScanNotice: some View {
        Label(
            "Scan stopped early — the sizes below cover only what was measured before stopping.",
            systemImage: "exclamationmark.circle"
        )
        .font(.callout)
        .foregroundStyle(.orange)
    }

    private var statCards: some View {
        HStack(spacing: 16) {
            StatCard(
                title: "Cleanable now",
                value: model.cleanableBytes.formattedBytes,
                subtitle: "What Reclaim can remove for you"
            )
            StatCard(
                title: "Total found",
                value: model.totalFoundBytes.formattedBytes,
                subtitle: "Including tool-managed items like Docker"
            )
            StatCard(
                title: "Selected",
                value: model.selectedBytes.formattedBytes,
                subtitle: "\(model.selection.count) item(s) ticked for cleaning"
            )
        }
    }

    // MARK: - Chart

    private var chartSection: some View {
        GroupBox("Space by category") {
            if model.isScanning {
                ProgressView("Scanning…")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                categoryChart
                    .padding(.top, 8)
            }
        }
    }

    private var categoryChart: some View {
        let totals = model.categoryTotals()
        return Chart(totals) { total in
            BarMark(
                x: .value("Size", Double(total.bytes)),
                y: .value("Category", total.category.title)
            )
            .foregroundStyle(.tint)
            .annotation(position: .trailing, alignment: .leading) {
                Text(total.bytes.formattedBytes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let bytes = value.as(Double.self) {
                        Text(Int64(bytes).formattedBytes)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
            }
        }
        .frame(height: CGFloat(totals.count) * 44 + 24)
    }

    // MARK: - Largest items

    private var largestSection: some View {
        GroupBox("Largest items") {
            let largest = model.largestTargets(limit: 6)
            if largest.isEmpty {
                Text(model.isScanning ? "Scanning…" : "Nothing measured yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 0) {
                    ForEach(largest) { target in
                        LargestItemRow(target: target) {
                            openCategory(target.category)
                        }
                        if target.id != largest.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Subviews

/// One headline number.
private struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }
}

/// One row in the "Largest items" list; clicking jumps to its category.
private struct LargestItemRow: View {
    @Environment(AppModel.self) private var model
    let target: CleanupTarget
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack {
                Image(systemName: target.category.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.name)
                    Text(target.category.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                SafetyBadge(level: target.safety)
                Text((model.status(of: target.id).bytes ?? 0).formattedBytes)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
