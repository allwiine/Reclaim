//
//  ProjectsView.swift
//  Reclaim
//
//  The dev-folder feature's screen, in the browser's two-column shape:
//  projects found in the user's development folders on the left, the
//  project inspector with per-artifact cherry-picking on the right.
//  Projects themselves are never cleanable — only their regenerable
//  artifacts. Inert (empty state) until a folder is added.
//

import AppKit
import ReclaimAppCore
import ReclaimKit
import SwiftUI

/// The folder-picking dialog shared by ProjectsView and Settings.
@MainActor
enum DevFolderPicker {
    static func pickFolders() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = localized("projects.addPrompt", defaultValue: "Add")
        panel.message = localized(
            "projects.addMessage",
            defaultValue: "Choose the folders where your development projects live."
        )
        return panel.runModal() == .OK ? panel.urls : []
    }
}

struct ProjectsView: View {
    @Environment(AppModel.self) private var model
    /// Opens the per-project clean confirmation ("Clean just this").
    var onCleanProject: (DiscoveredProject) -> Void = { _ in }

    private enum SortOrder: Hashable {
        case bySize, byActivity
    }

    @State private var sortOrder: SortOrder = .bySize
    @State private var inspectedProjectID: DiscoveredProject.ID?

    var body: some View {
        Group {
            if model.devRoots.isEmpty {
                emptyState
            } else {
                browser
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.gearshape")
                .scaledFont(size: 34, weight: .light)
                .foregroundStyle(Theme.textTertiary)
            Text(localized("projects.empty.title", defaultValue: "Find forgotten projects"))
                .scaledFont(size: 16, weight: .semibold)
                .foregroundStyle(Theme.textPrimary)
            Text(localized(
                "projects.empty.body",
                defaultValue: "Add the folders where your projects live. Reclaim finds git repositories and regenerable artifacts like node_modules and build folders, and shows what each project last did."
            ))
            .themeFont(.body)
            .lineSpacing(3.5)
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: 420)
            Button(localized("projects.addFolder", defaultValue: "Add a development folder…")) {
                for url in DevFolderPicker.pickFolders() {
                    model.addDevRoot(url)
                }
            }
            .buttonStyle(.rcPrimary)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private var sortedProjects: [DiscoveredProject] {
        switch sortOrder {
        case .bySize:
            model.projects.sorted { $0.artifactBytes > $1.artifactBytes }
        case .byActivity:
            model.projects.sorted {
                ($0.lastActivityDate ?? .distantPast) < ($1.lastActivityDate ?? .distantPast)
            }
        }
    }

    private var failedRoots: [DevRootScan] {
        model.projectScans.filter { $0.failureMessage != nil }
    }

    /// The row the detail column shows: the clicked one, else the first.
    private var inspectedProject: DiscoveredProject? {
        sortedProjects.first { $0.id == inspectedProjectID } ?? sortedProjects.first
    }

    // MARK: - Browser

    private var browser: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                strip

                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)

                listColumn
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Theme.divider)
                .frame(width: 1)

            ProjectInspectorPanel(
                project: inspectedProject,
                onCleanProject: onCleanProject
            )
            .frame(width: 336)
        }
    }

    // MARK: - Strip

    private var strip: some View {
        HStack(spacing: 10) {
            Picker(localized("projects.sortLabel", defaultValue: "Sort"), selection: $sortOrder) {
                Text(localized("projects.sortBySize", defaultValue: "Largest first"))
                    .tag(SortOrder.bySize)
                Text(localized("projects.sortByActivity", defaultValue: "Longest inactive first"))
                    .tag(SortOrder.byActivity)
            }
            .pickerStyle(.menu)
            .fixedSize()

            Button(localized("projects.selectAllArtifacts", defaultValue: "Select all")) {
                model.selectAllArtifacts()
            }
            .buttonStyle(StripChipButtonStyle())
            .disabled(model.isScanning || model.isCleaning || model.selectableArtifactCount == 0)

            Button(localized("browser.clear", defaultValue: "Clear")) {
                model.clearArtifactSelection()
            }
            .buttonStyle(StripChipButtonStyle(plain: true))
            .disabled(model.selectedArtifacts.isEmpty)

            Spacer()

            Text(selectionSummary)
                .scaledFont(size: 12)
                .monospacedDigit()
                .foregroundStyle(Theme.textLabel)
                .contentTransition(.numericText())
                .animation(Theme.smooth, value: model.selectedArtifactBytes)

            Button(localized("projects.addFolder", defaultValue: "Add a development folder…")) {
                for url in DevFolderPicker.pickFolders() {
                    model.addDevRoot(url)
                }
            }
            .buttonStyle(.rcSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    /// Scoped to the artifacts this screen lists — never the registry
    /// selection (that count lives in the category browser).
    private var selectionSummary: String {
        let picked = model.selectedArtifacts.count
        guard picked > 0 else {
            return localized("browser.noItemsSelected", defaultValue: "No items selected")
        }
        return localized(
            "browser.selectionSummary",
            defaultValue: "\(picked) of \(model.selectableArtifactCount) items selected · \(model.selectedArtifactBytes.formattedBytesCompact)"
        )
    }

    // MARK: - List column

    private var listColumn: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(failedRoots) { scan in
                    failedRootRow(scan)
                }

                if model.lastScan == nil {
                    hintText(localized(
                        "projects.notScanned",
                        defaultValue: "Run a scan to find projects and artifacts."
                    ))
                } else if model.projects.isEmpty {
                    hintText(localized(
                        "projects.noneFound",
                        defaultValue: "No projects found in the added folders."
                    ))
                } else {
                    ForEach(sortedProjects) { project in
                        ProjectRow(
                            project: project,
                            isInspected: inspectedProject?.id == project.id,
                            maxBytes: sortedProjects.map(\.artifactBytes).max() ?? 0
                        ) {
                            inspectedProjectID = project.id
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 20)
        }
    }

    private func hintText(_ text: String) -> some View {
        Text(text)
            .themeFont(.body)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func failedRootRow(_ scan: DevRootScan) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .scaledFont(size: 12)
                .foregroundStyle(Theme.cautionTitle)
            Text((scan.root.path as NSString).abbreviatingWithTildeInPath)
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.textSecondary)
            Text(scan.failureMessage ?? "")
                .themeFont(.caption)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .card(radius: Theme.radiusInset)
        .padding(.bottom, 6)
    }
}

// MARK: - Row

/// One project row: tri-state checkbox, name + stale badge + activity,
/// artifact size + relative bar.
private struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    let project: DiscoveredProject
    let isInspected: Bool
    let maxBytes: Int64
    let inspect: () -> Void

    var body: some View {
        Button(action: inspect) {
            HStack(spacing: 12) {
                checkbox

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(project.name)
                            .scaledFont(size: 13.5, weight: .medium)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if model.isProjectStale(project) {
                            StaleBadge()
                        }
                    }
                    Text(activityLine)
                        .themeFont(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                trailing
                    .frame(width: 96, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                isInspected ? Color.white.opacity(0.075) : .clear,
                in: RoundedRectangle(cornerRadius: Theme.radiusInset)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusInset))
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: Theme.radiusInset, color: Color.white.opacity(0.055))
        .animation(Theme.quick, value: isInspected)
        .contextMenu { contextMenu }
    }

    private var activityLine: String {
        var parts: [String] = [
            (project.url.path as NSString).abbreviatingWithTildeInPath,
        ]
        if let edited = project.lastEditDate {
            parts.append(localized(
                "projects.lastEdited",
                defaultValue: "Edited \(edited.formatted(.relative(presentation: .named)))"
            ))
        }
        if let git = project.lastGitActivityDate {
            parts.append(localized(
                "projects.lastCommit",
                defaultValue: "Git activity \(git.formatted(.relative(presentation: .named)))"
            ))
        }
        return parts.joined(separator: " · ")
    }

    private var checkbox: some View {
        Toggle(
            localized("browser.selectAccessibility", defaultValue: "Select \(project.name)"),
            isOn: Binding(
                get: { model.isProjectSelected(project) },
                set: { model.setProjectSelected(project, $0) }
            )
        )
        .toggleStyle(CheckboxToggleStyle(mixed: model.isProjectPartiallySelected(project)))
        .labelsHidden()
        .disabled(!model.isProjectSelectable(project))
        .opacity(model.isProjectSelectable(project) ? 1 : 0.35)
    }

    @ViewBuilder
    private var trailing: some View {
        if project.artifactBytes > 0 {
            VStack(alignment: .trailing, spacing: 5) {
                Text(project.artifactBytes.formattedBytesCompact)
                    .scaledFont(size: 13, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                MiniBar(
                    fraction: maxBytes > 0
                        ? Double(project.artifactBytes) / Double(maxBytes) : 0,
                    color: Theme.safe
                )
            }
        } else {
            Text(verbatim: "—")
                .scaledFont(size: 12)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(localized("projects.revealInFinder", defaultValue: "Reveal in Finder")) {
            NSWorkspace.shared.activateFileViewerSelecting([project.url])
        }
        Button(localized("browser.copyPaths", defaultValue: "Copy \(1) Paths")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(project.url.path, forType: .string)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Empty", traits: .fixedLayout(width: 900, height: 620)) {
    ProjectsView()
        .background(Theme.background)
        .environment(PreviewData.idle())
        .preferredColorScheme(.dark)
}

#Preview("Browser", traits: .fixedLayout(width: 1060, height: 810)) {
    ProjectsView()
        .background(Theme.background)
        .environment(PreviewData.scannedWithProjects())
        .preferredColorScheme(.dark)
}
#endif
