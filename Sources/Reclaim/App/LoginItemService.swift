//
//  LoginItemService.swift
//  Reclaim
//
//  Wraps SMAppService for the "open at login" setting, so weekly
//  background scans and the menu bar summary are available without the
//  user launching the app themselves.
//

import Foundation
import ServiceManagement

enum LoginItemService {
    /// SMAppService needs a real app bundle; under `swift run` there is
    /// none, so the Settings row hides itself entirely.
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
