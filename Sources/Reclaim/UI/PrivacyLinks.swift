//
//  PrivacyLinks.swift
//  Reclaim
//
//  Shared deep links into System Settings.
//

import Foundation

enum PrivacyLinks {
    /// System Settings → Privacy & Security → Full Disk Access.
    static let fullDiskAccess =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// System Settings → Notifications.
    static let notifications =
        URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
}
