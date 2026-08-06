//
//  RunningTools.swift
//  Reclaim
//
//  Detects when apps that own selected cleanup data are running, so
//  the pre-clean confirmation can warn about disrupting in-progress
//  work. A soft warning by design — an idle open app is harmless, so
//  the user decides.
//

import AppKit
import ReclaimKit

enum RunningTools {
    /// Display names of running apps related to the given targets,
    /// de-duplicated, in the order the targets reference them.
    static func runningRelatedApps(for targets: [CleanupTarget]) -> [String] {
        let running = NSWorkspace.shared.runningApplications
        var byBundleID: [String: String] = [:]
        for app in running {
            if let id = app.bundleIdentifier {
                byBundleID[id] = app.localizedName ?? id
            }
        }

        var seen = Set<String>()
        var names: [String] = []
        for target in targets {
            for bundleID in target.relatedAppBundleIDs {
                if let name = byBundleID[bundleID], seen.insert(name).inserted {
                    names.append(name)
                }
            }
        }
        return names
    }

    /// Warning sentence for the confirmation dialog, or `nil` when no
    /// related app is running.
    static func warning(for targets: [CleanupTarget]) -> String? {
        let names = runningRelatedApps(for: targets)
        guard !names.isEmpty else { return nil }
        let list = names.formatted(.list(type: .and))
        return localized(
            "confirm.runningAppsWarning",
            defaultValue: "\(list) appears to be running — cleaning its data now may break builds or work in progress. Consider quitting first."
        )
    }
}
