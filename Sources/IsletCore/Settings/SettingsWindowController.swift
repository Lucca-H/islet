import AppKit
import SwiftUI

/// Lazily builds and shows the Settings window. Islet is an accessory (menu-bar)
/// app, so we temporarily promote it to a regular app while the window is open.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let root = SettingsView().environmentObject(SettingsStore.shared)
            let hosting = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: hosting)
            win.title = "Islet Settings"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.isReleasedWhenClosed = false
            win.center()
            win.delegate = self
            window = win
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Return to the menu-bar-only footprint once settings closes.
        NSApp.setActivationPolicy(.accessory)
    }
}
