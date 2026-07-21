import AppKit

/// The menu-bar item: quick access to Settings and Quit, plus a home for the app
/// when it's otherwise living entirely in the notch.
@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Islet")
            button.image?.isTemplate = true
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About Islet", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Islet", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func openAbout() { SettingsWindowController.shared.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
