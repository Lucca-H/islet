import Foundation
import ServiceManagement
import os

/// Thin wrapper around `SMAppService` for a login item that starts the main app.
enum LaunchAtLogin {
    private static let log = Logger(subsystem: "com.dynamicisland.islet", category: "LaunchAtLogin")

    static var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }
            return false
        }
        set {
            guard #available(macOS 13.0, *) else { return }
            do {
                if newValue {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                log.error("Failed to update login item: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
