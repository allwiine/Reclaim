//
//  RootView.swift
//  Reclaim
//
//  Top-level navigation: sidebar + detail, plus the global toolbar,
//  the pre-clean confirmation dialog, and the post-clean summary alert.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

/// Sidebar destinations.
enum SidebarItem: Hashable {
    case overview
    case category(ToolCategory)
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .overview
    @State private var isConfirmingClean = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            detailView
        }
        .navigationTitle("Reclaim")
        .toolbar { toolbarContent }
        .confirmationDialog(
            confirmationTitle,
            isPresented: $isConfirmingClean,
            titleVisibility: .visible
        ) {
            Button(
                model.disposal == .trash ? "Move to Trash" : "Delete Permanently",
                role: .destructive
            ) {
                model.cleanSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .alert(
            "Cleanup finished",
            isPresented: summaryIsPresented,
            presenting: model.lastCleanSummary
        ) { _ in
            Button("OK") {}
        } message: { summary in
            Text(summary.message)
        }
        .safeAreaInset(edge: .bottom) {
            if let progress = model.cleanProgress {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Cleaning \(progress.targetName) (\(progress.index) of \(progress.total))…")
                        .font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .overview {
        case .overview:
            OverviewView(openCategory: { selection = .category($0) })
        case .category(let category):
            CategoryView(category: category)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("Select All Safe Items") { model.selectAllSafe() }
                    .disabled(model.lastScan == nil)
                Button("Deselect All") { model.clearSelection() }
                    .disabled(model.selection.isEmpty)
            } label: {
                Label("Select", systemImage: "checklist")
            }

            if model.isScanning {
                Button {
                    model.cancelScan()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .help("Stop the current scan")
            } else if model.isCleaning {
                Button {
                    model.cancelClean()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .help("Finish the current item, then stop cleaning")
            } else {
                Button {
                    model.scanAll()
                } label: {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .help("Measure every known cache and tool location")
            }

            Button {
                isConfirmingClean = true
            } label: {
                Label(cleanButtonTitle, systemImage: "trash")
            }
            .disabled(model.selection.isEmpty || model.isScanning || model.isCleaning)
            .help("Clean the selected items")
        }
    }

    private var cleanButtonTitle: String {
        model.selectedBytes > 0
            ? "Clean \(model.selectedBytes.formattedBytes)"
            : "Clean"
    }

    // MARK: - Confirmation & summary

    private var confirmationTitle: String {
        let count = model.selection.count
        return "Clean \(count) item\(count == 1 ? "" : "s")?"
    }

    private var confirmationMessage: String {
        let size = model.selectedBytes > 0
            ? "About \(model.selectedBytes.formattedBytes) will be reclaimed. "
            : ""
        var message = switch model.disposal {
        case .trash:
            size + "Items are moved to the Trash, so this can be undone until the Trash is emptied."
        case .delete:
            size + "Items are deleted permanently. This cannot be undone."
        }
        if let warning = RunningTools.warning(for: model.selectedTargets) {
            message += "\n\n⚠️ " + warning
        }
        return message
    }

    private var summaryIsPresented: Binding<Bool> {
        Binding(
            get: { model.lastCleanSummary != nil },
            set: { if !$0 { model.lastCleanSummary = nil } }
        )
    }
}
