import AppKit
import IsletCore

// Islet runs as a menu-bar/accessory app: no Dock icon, no default window — just
// the notch surface and a status-bar item. Top-level code executes on the main
// thread, so we assert main-actor isolation to construct the delegate.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
