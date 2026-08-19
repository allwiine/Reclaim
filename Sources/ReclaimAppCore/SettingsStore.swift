//
//  SettingsStore.swift
//  ReclaimAppCore
//
//  UserDefaults-backed settings, split out of AppModel so the god
//  class sheds its persistence plumbing while behavior stays identical.
//

import Foundation
import Observation
import ReclaimKit

@MainActor
@Observable
public final class SettingsStore {
    private let defaults: UserDefaults

    private enum DefaultsKey {
        static let disposal = "settings.disposal"
        static let showNotInstalled = "settings.showNotInstalled"
        static let showEmpty = "settings.showEmpty"
        static let preselectCaution = "settings.preselectCaution"
        static let dryRun = "settings.dryRun"
        static let weeklyScan = "settings.weeklyScan"
        static let notifyLargeReclaimable = "settings.notifyLargeReclaimable"
        static let menuBarExtra = "settings.menuBarExtra"
    }

    /// Reads a Bool setting through the ObservationRegistrar so views
    /// update when it changes; `fallback` applies when never set.
    private func boolSetting<Member>(
        _ keyPath: KeyPath<SettingsStore, Member>, key: String, fallback: Bool
    ) -> Bool {
        access(keyPath: keyPath)
        return defaults.object(forKey: key) as? Bool ?? fallback
    }

    private func setBoolSetting<Member>(
        _ keyPath: KeyPath<SettingsStore, Member>, key: String, to newValue: Bool
    ) {
        // Skip no-op writes: SwiftUI bindings (e.g. MenuBarExtra's
        // isInserted) can re-assign the current value during scene
        // evaluation, and an unconditional withMutation would spin an
        // invalidate-reevaluate loop.
        guard (defaults.object(forKey: key) as? Bool) != newValue else { return }
        withMutation(keyPath: keyPath) {
            defaults.set(newValue, forKey: key)
        }
    }

    /// Trash (default) or permanent deletion. Backed by UserDefaults via
    /// the ObservationRegistrar so views update when Settings change it.
    public var disposal: Disposal {
        get {
            access(keyPath: \.disposal)
            let raw = defaults.string(forKey: DefaultsKey.disposal) ?? ""
            return Disposal(rawValue: raw) ?? .trash
        }
        set {
            guard newValue != disposal else { return }
            withMutation(keyPath: \.disposal) {
                defaults.set(newValue.rawValue, forKey: DefaultsKey.disposal)
            }
        }
    }

    /// Whether tools that were not found on this Mac stay visible.
    public var showNotInstalled: Bool {
        get { boolSetting(\.showNotInstalled, key: DefaultsKey.showNotInstalled, fallback: false) }
        set { setBoolSetting(\.showNotInstalled, key: DefaultsKey.showNotInstalled, to: newValue) }
    }

    /// Whether locations the last scan measured as empty stay visible.
    /// Off by default — a clean row disappearing is the reward.
    public var showEmpty: Bool {
        get { boolSetting(\.showEmpty, key: DefaultsKey.showEmpty, fallback: false) }
        set { setBoolSetting(\.showEmpty, key: DefaultsKey.showEmpty, to: newValue) }
    }

    /// Whether Caution-rated items join the post-scan preselection.
    /// Off by default — only Safe items come ticked after a scan.
    public var preselectCaution: Bool {
        get { boolSetting(\.preselectCaution, key: DefaultsKey.preselectCaution, fallback: false) }
        set { setBoolSetting(\.preselectCaution, key: DefaultsKey.preselectCaution, to: newValue) }
    }

    /// Report what a clean pass would remove without touching anything.
    public var dryRun: Bool {
        get { boolSetting(\.dryRun, key: DefaultsKey.dryRun, fallback: false) }
        set { setBoolSetting(\.dryRun, key: DefaultsKey.dryRun, to: newValue) }
    }

    /// Re-scan automatically once a week while Reclaim is running.
    public var weeklyScanEnabled: Bool {
        get { boolSetting(\.weeklyScanEnabled, key: DefaultsKey.weeklyScan, fallback: true) }
        set { setBoolSetting(\.weeklyScanEnabled, key: DefaultsKey.weeklyScan, to: newValue) }
    }

    /// Post a notification when a background scan finds more than
    /// ``notificationThresholdBytes`` reclaimable.
    public var notifyLargeReclaimable: Bool {
        get { boolSetting(\.notifyLargeReclaimable, key: DefaultsKey.notifyLargeReclaimable, fallback: false) }
        set { setBoolSetting(\.notifyLargeReclaimable, key: DefaultsKey.notifyLargeReclaimable, to: newValue) }
    }

    /// Whether the compact menu bar summary is shown.
    public var menuBarExtraEnabled: Bool {
        get { boolSetting(\.menuBarExtraEnabled, key: DefaultsKey.menuBarExtra, fallback: true) }
        set { setBoolSetting(\.menuBarExtraEnabled, key: DefaultsKey.menuBarExtra, to: newValue) }
    }

    /// Reclaimable size that qualifies as "worth a notification".
    public static let notificationThresholdBytes: Int64 = 25_000_000_000

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }
}
