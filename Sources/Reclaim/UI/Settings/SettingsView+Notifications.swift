//
//  SettingsView+Notifications.swift
//  Reclaim
//
//  Notification-permission plumbing for the "notify when large" setting.
//

import UserNotifications

extension SettingsView {
    // MARK: - Notifications plumbing

    /// UNUserNotificationCenter requires a real app bundle; `swift run`
    /// has none and would crash.
    var notificationCenterAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    func refreshNotificationStatus() async {
        guard notificationCenterAvailable else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsDenied = settings.authorizationStatus == .denied
    }

    func requestNotificationAuthorization() async {
        guard notificationCenterAvailable else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
    }
}
