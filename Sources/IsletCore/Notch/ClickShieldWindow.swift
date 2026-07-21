import AppKit

/// A transparent, screen-spanning panel that sits just below the notch while it
/// is expanded. It exists only to swallow the dismissing click: clicking away
/// closes the notch and does nothing else, so the button underneath is never
/// pressed — the way an open menu eats the click that dismisses it.
///
/// A global `NSEvent` monitor can't do this; it observes other apps' clicks but
/// cannot consume them. Capturing the click in a window of our own can, and
/// unlike a CGEvent tap it needs no Accessibility permission.
final class ClickShieldWindow: NSPanel {
    private final class ShieldView: NSView {
        var onClick: (() -> Void)?
        override func mouseDown(with event: NSEvent) { onClick?() }
        override func rightMouseDown(with event: NSEvent) { onClick?() }
        override func otherMouseDown(with event: NSEvent) { onClick?() }
    }

    private let shieldView = ShieldView()

    init(onClick: @escaping () -> Void) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // One below the notch window, so the notch's own content still gets its
        // clicks, but above the menu bar and ordinary windows.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        shieldView.onClick = onClick
        contentView = shieldView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Cover the union of every screen, so a click anywhere lands here first.
    func show() {
        let frame = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        guard !frame.isEmpty else { return }
        setFrame(frame, display: false)
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}
