//
//  ToolbarView.swift
//  Reclaim
//
//  The content column's header strip: view title + subtitle on the
//  left, search / rescan / the primary Reclaim action on the right.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

struct ToolbarView: View {
    @Environment(AppModel.self) private var model
    let destination: Destination
    let phase: ContentPhase
    @Binding var searchText: String
    let onReclaim: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.opacity)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textLabel)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 12)

            if showsActions {
                searchField

                Button {
                    model.scanAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.rcIcon)
                .help("Scan again")
                .keyboardShortcut("r", modifiers: .command)

                Button(reclaimLabel) {
                    onReclaim()
                }
                .buttonStyle(CompactPrimaryButtonStyle(
                    enabled: model.selectedBytes > 0 || !model.selection.isEmpty
                ))
                .disabled(model.selection.isEmpty)
                .help("Clean the selected items")
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .frame(height: Theme.toolbarHeight)
        .background(Color.white.opacity(0.02))
        .animation(Theme.quick, value: showsActions)
    }

    // MARK: - Pieces

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(Color(hex: 0x8B8B92))
            TextField("Search paths", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .focused($searchFocused)
                .frame(width: 110)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: Theme.radiusChip))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusChip)
                .strokeBorder(.white.opacity(searchFocused ? 0.2 : 0.06), lineWidth: 0.5)
        }
        .animation(Theme.quick, value: searchFocused)
    }

    private var showsActions: Bool {
        phase == .overview || phase == .browser
    }

    private var reclaimLabel: String {
        model.selectedBytes > 0
            ? "Reclaim \(model.selectedBytes.formattedBytesCompact)"
            : model.selection.isEmpty ? "Nothing selected" : "Reclaim selection"
    }

    // MARK: - Titles

    private var title: String {
        switch phase {
        case .idle: "Reclaim"
        case .scanning: "Scanning"
        case .cleaning: model.disposal == .trash ? "Moving to Trash" : "Cleaning"
        case .done: "Finished"
        case .overview: "Overview"
        case .browser: browserTitle
        case .history: "History"
        case .settings: "Settings"
        }
    }

    private var browserTitle: String {
        if !searchText.isEmpty { return "Search" }
        if case .category(let category) = destination { return category.title }
        return "Results"
    }

    private var subtitle: String {
        switch phase {
        case .idle:
            return "No scan yet"
        case .overview:
            guard let lastScan = model.lastScan else { return "" }
            let when = lastScan.formatted(.relative(presentation: .named))
            let measured = model.targets.count { model.bytes(of: $0) > 0 }
            return "Scanned \(when) · \(measured) locations"
        case .browser:
            if !searchText.isEmpty { return "" }
            guard case .category(let category) = destination else { return "" }
            let targets = model.visibleTargets(in: category)
            let bytes = targets.reduce(Int64(0)) { $0 + model.bytes(of: $1) }
            return "\(targets.count) items · \(bytes.formattedBytesCompact)"
        case .history:
            let recent = model.history.count
            return recent == 0 ? "" : "\(recent) clean\(recent == 1 ? "" : "s") on record"
        default:
            return ""
        }
    }
}

/// Toolbar-sized primary button: 26 pt, greyed when nothing is selected.
private struct CompactPrimaryButtonStyle: ButtonStyle {
    let enabled: Bool
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(enabled ? Theme.onAccent : Theme.textQuaternary)
            .padding(.horizontal, 13)
            .frame(height: 26)
            .background {
                if enabled {
                    RoundedRectangle(cornerRadius: Theme.radiusChip)
                        .fill(Theme.accentGradient)
                } else {
                    RoundedRectangle(cornerRadius: Theme.radiusChip)
                        .fill(Color.white.opacity(0.06))
                }
            }
            .shadow(color: enabled ? Theme.accent.opacity(0.35) : .clear, radius: 5, y: 2)
            .brightness(isHovered && enabled ? 0.06 : 0)
            .scaleEffect(configuration.isPressed && enabled ? 0.97 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
            .animation(Theme.quick, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Toolbar", traits: .sizeThatFitsLayout) {
    @Previewable @State var search = ""
    VStack(spacing: 0) {
        ToolbarView(
            destination: .overview,
            phase: .overview,
            searchText: $search,
            onReclaim: {}
        )
    }
    .frame(width: 1000)
    .background(Theme.background)
    .environment(PreviewData.scanned())
    .preferredColorScheme(.dark)
}
#endif
