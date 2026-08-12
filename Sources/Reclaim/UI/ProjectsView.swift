//
//  ProjectsView.swift
//  Reclaim
//
//  The dev-folder feature's screen: projects found in the user's
//  development folders, listed by size and activity, with per-artifact
//  checkboxes. Projects themselves are never cleanable — only their
//  regenerable artifacts. Inert (empty state) until a folder is added.
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

    private enum SortOrder: Hashable {
        case bySize, byActivity
    }

    @State private var sortOrder: SortOrder = .bySize
    @State private var expandedProjectIDs: Set<String> = []

    var body: some View {
        Group {
            if model.devRoots.isEmpty {
                emptyState
            } else {
                projectList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(localized("projects.empty.title", defaultValue: "Find forgotten projects"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(localized(
                "projects.empty.body",
                defaultValue: "Add the folders where your projects live. Reclaim finds git repositories and regenerable artifacts like node_modules and build folders, and shows what each project last did."
            ))
            .font(Theme.body)
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

    // MARK: - Project list

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

    private var projectList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                listHeader

                ForEach(failedRoots) { scan in
                    failedRootRow(scan)
                }

                if model.lastScan == nil {
                    Text(localized(
                        "projects.notScanned",
                        defaultValue: "Run a scan to find projects and artifacts."
                    ))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 8)
                } else if model.projects.isEmpty {
                    Text(localized(
                        "projects.noneFound",
                        defaultValue: "No projects found in the added folders."
                    ))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(sortedProjects) { project in
                            projectRow(project)
                            if project.id != sortedProjects.last?.id {
                                Rectangle().fill(Theme.separator).frame(height: 1)
                            }
                        }
                    }
                    .card(radius: Theme.radiusPanel)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
    }

    private var listHeader: some View {
        HStack(spacing: 10) {
            Picker(localized("projects.sortLabel", defaultValue: "Sort"), selection: $sortOrder) {
                Text(localized("projects.sortBySize", defaultValue: "Largest first"))
                    .tag(SortOrder.bySize)
                Text(localized("projects.sortByActivity", defaultValue: "Longest inactive first"))
                    .tag(SortOrder.byActivity)
            }
            .pickerStyle(.menu)
            .fixedSize()
            Spacer()
            Button(localized("projects.addFolder", defaultValue: "Add a development folder…")) {
                for url in DevFolderPicker.pickFolders() {
                    model.addDevRoot(url)
                }
            }
            .buttonStyle(.rcSecondary)
        }
    }

    private func failedRootRow(_ scan: DevRootScan) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(Theme.cautionTitle)
            Text((scan.root.path as NSString).abbreviatingWithTildeInPath)
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.textSecondary)
            Text(scan.failureMessage ?? "")
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .card(radius: Theme.radiusPanel)
    }

    // MARK: - Rows

    private func projectRow(_ project: DiscoveredProject) -> some View {
        let isExpanded = expandedProjectIDs.contains(project.id)
        return VStack(spacing: 0) {
            Button {
                if isExpanded {
                    expandedProjectIDs.remove(project.id)
                } else {
                    expandedProjectIDs.insert(project.id)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textQuaternary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(project.name)
                                .font(Theme.rowTitle)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            if model.isProjectStale(project) {
                                Text(localized("projects.staleBadge", defaultValue: "No recent activity"))
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.cautionTitle)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Theme.cautionTitle.opacity(0.12),
                                        in: Capsule()
                                    )
                            }
                        }
                        Text(activityLine(project))
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(project.artifactBytes > 0
                        ? project.artifactBytes.formattedBytesCompact
                        : "—")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: 0x8E8E95))
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([project.url])
                    } label: {
                        Image(systemName: "magnifyingglass.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help(localized("projects.revealInFinder", defaultValue: "Reveal in Finder"))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                artifactRows(of: project)
            }
        }
        .animation(Theme.quick, value: isExpanded)
    }

    private func activityLine(_ project: DiscoveredProject) -> String {
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

    @ViewBuilder
    private func artifactRows(of project: DiscoveredProject) -> some View {
        if project.artifacts.isEmpty {
            Text(localized("projects.noArtifacts", defaultValue: "No regenerable artifacts found."))
                .font(Theme.caption)
                .foregroundStyle(Theme.textQuaternary)
                .padding(.horizontal, 40)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(project.artifacts) { artifact in
                artifactRow(artifact)
            }
            .padding(.bottom, 6)
        }
    }

    private func artifactRow(_ artifact: DiscoveredArtifact) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { model.isArtifactSelected(artifact) },
                set: { model.setArtifactSelected(artifact, $0) }
            )) {
                Text(artifact.kind?.name ?? artifact.kindID)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
            }
            .toggleStyle(.checkbox)
            .disabled(!model.isArtifactSelectable(artifact))
            Text(artifact.url.lastPathComponent)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textQuaternary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(artifact.measurement.bytes.formattedBytesCompact)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Color(hex: 0x8E8E95))
        }
        .padding(.leading, 40)
        .padding(.trailing, 14)
        .padding(.vertical, 5)
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
#endif
