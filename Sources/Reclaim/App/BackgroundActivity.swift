//
//  BackgroundActivity.swift
//  Reclaim
//
//  Weekly background scanning while the app is open, and the optional
//  "lots to reclaim" notification. The *decision* of when a scan is
//  due lives in AppModel (tested); this file is just the clock and
//  the notification plumbing.
//

import Foundation
import os
import ReclaimAppCore
import ReclaimKit
import UserNotifications

enum BackgroundActivity {
    /// How often the due-check runs while the app is open.
    static let checkInterval: Duration = .seconds(30 * 60)

    /// Loops for the app's lifetime: starts a background scan when one
    /// is due, then notifies about the result if the user opted in.
    @MainActor
    static func run(model: AppModel) async {
        while !Task.isCancelled {
            if model.settings.weeklyScanEnabled, !model.activity.isScanning, !model.activity.isCleaning {
                let before = model.results.lastScan
                model.scanner.runBackgroundScanIfDue()
                if model.activity.isScanning {
                    // Wait for this scan to land, then evaluate the result.
                    while model.activity.isScanning, !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                    }
                    if model.results.lastScan != before {
                        await notifyIfWorthwhile(model: model)
                    }
                }
            }
            try? await Task.sleep(for: checkInterval)
        }
    }

    /// Post a notification when the scan found more than the threshold.
    @MainActor
    private static func notifyIfWorthwhile(model: AppModel) async {
        guard model.settings.notifyLargeReclaimable,
              model.cleanableBytes > SettingsStore.notificationThresholdBytes,
              // UNUserNotificationCenter requires a real app bundle;
              // `swift run` has none and would crash.
              Bundle.main.bundleIdentifier != nil else { return }

        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = localized(
            "notification.title",
            defaultValue: "Reclaim found \(model.cleanableBytes.formattedBytesCompact)"
        )
        content.body = localized(
            "notification.body",
            defaultValue: "Developer caches are holding on to space. Review and reclaim it when convenient."
        )
        let request = UNNotificationRequest(
            identifier: "reclaim.background-scan",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
        Log.app.info("Posted background scan notification")
    }
}
