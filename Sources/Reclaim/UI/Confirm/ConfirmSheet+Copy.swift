//
//  ConfirmSheet+Copy.swift
//  Reclaim
//
//  The sheet's headline copy: the title, the explanatory body text,
//  and the risky/running-app warning banner.
//

import ReclaimAppCore
import ReclaimKit
import SwiftUI

extension ConfirmSheet {
    // MARK: - Content

    func title(_ picked: [CleanupTarget]) -> String {
        if let target = singleTarget {
            let space = model.selection.selectedBytes(of: target).formattedBytesCompact
            if let counts = model.selection.partialSelectionCounts(of: target) {
                let scope = localized(
                    "format.itemsOf",
                    defaultValue: "\(counts.selected) of \(counts.total) items"
                )
                return localized(
                    "confirm.titleSinglePartial",
                    defaultValue: "Reclaim \(space) from \(scope) in \(target.name)?"
                )
            }
            return localized(
                "confirm.titleSingle",
                defaultValue: "Reclaim \(space) from \(target.name)?"
            )
        }
        if let project = singleProject {
            let space = model.projects.selectedArtifactBytes(of: project).formattedBytesCompact
            if let counts = model.projects.partialSelectionCounts(of: project) {
                let scope = localized(
                    "format.itemsOf",
                    defaultValue: "\(counts.selected) of \(counts.total) items"
                )
                return localized(
                    "confirm.titleSinglePartial",
                    defaultValue: "Reclaim \(space) from \(scope) in \(project.name)?"
                )
            }
            return localized(
                "confirm.titleSingle",
                defaultValue: "Reclaim \(space) from \(project.name)?"
            )
        }
        let space = model.selectedBytes.formattedBytesCompact
        let locationCount = picked.count + model.projects.selectedArtifacts.count
        return model.settings.dryRun
            ? localized(
                "confirm.titleDryRun",
                defaultValue: "Dry run: reclaim \(space) from \(locationCount) locations?"
            )
            : localized(
                "confirm.title",
                defaultValue: "Reclaim \(space) from \(locationCount) locations?"
            )
    }

    func bodyText(toTrash: Bool) -> String {
        if model.settings.dryRun {
            return localized(
                "confirm.bodyDryRun",
                defaultValue: "Dry run is on — Reclaim will only report what would be removed. Nothing is touched."
            )
        }
        if let target = singleTarget {
            if model.selection.isPartiallySelected(target) {
                return localized(
                    "confirm.bodySinglePartial",
                    defaultValue: "Only the items listed below are affected. The rest of \(target.name) stays where it is."
                )
            }
            return toTrash
                ? localized(
                    "confirm.bodySingleTrash",
                    defaultValue: "This one location moves to the Trash. Nothing else in your selection is touched."
                )
                : localized(
                    "confirm.bodySingleDelete",
                    defaultValue: "This one location is deleted immediately and cannot be recovered."
                )
        }
        if let project = singleProject, model.projects.isProjectPartiallySelected(project) {
            return localized(
                "confirm.bodySinglePartial",
                defaultValue: "Only the items listed below are affected. The rest of \(project.name) stays where it is."
            )
        }
        return toTrash
            ? localized(
                "confirm.bodyTrash",
                defaultValue: "Everything listed below moves to the Trash. Nothing is removed permanently until you empty it."
            )
            : localized(
                "confirm.bodyDelete",
                defaultValue: "Everything listed below is deleted immediately and cannot be recovered."
            )
    }

    func warningText(_ picked: [CleanupTarget]) -> String? {
        var lines: [String] = []
        if picked.contains(where: { $0.safety == .destructive }) {
            lines.append(localized(
                "confirm.destructiveWarning",
                defaultValue: "This selection includes items marked Destructive — things you created, like emulators, that cannot be restored."
            ))
        } else if picked.contains(where: { $0.safety == .caution }) {
            lines.append(localized(
                "confirm.cautionWarning",
                defaultValue: "This selection includes items marked Caution. They can be restored, but re-downloading models or losing history costs something."
            ))
        }
        if let running = RunningTools.warning(for: picked) {
            lines.append(running)
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }
}
