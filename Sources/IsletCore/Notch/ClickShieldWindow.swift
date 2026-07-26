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
    /// A click is a *pair* of events. Consuming only the mouse-down and standing
    /// down immediately left the matching mouse-up to land on whatever was behind
    /// the shield — so the click wasn't nullified, just split in half, and anything
    /// that acts on mouse-up (web and Electron UIs especially) still fired.
    /// The view therefore reports the up as well, and the window defers going away
    /// until it arrives.
    private final class ShieldView: NSView {
        var onClick: (() -> Void)?
        var onClickFinished: (() -> Void)?

        /// Islet is a background app and is essentially never frontmost, so every
        /// click the shield sees is a "first mouse" — the click that would normally
        /// activate an inactive app rather than be delivered to its view. Without
        /// this the shield's whole reason to exist is unreliable.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) { onClick?() }
        override func rightMouseDown(with event: NSEvent) { onClick?() }
        override func otherMouseDown(with event: NSEvent) { onClick?() }

        override func mouseUp(with event: NSEvent) { onClickFinished?() }
        override func rightMouseUp(with event: NSEvent) { onClickFinished?() }
        override func otherMouseUp(with event: NSEvent) { onClickFinished?() }
        // Swallowed too: a press-drag-release across the shield shouldn't leak a
        // drag to whatever is underneath either.
        override func mouseDragged(with event: NSEvent) {}
    }

    private let shieldView = ShieldView()
    /// Set between the mouse-down the shield consumed and its mouse-up, during which
    /// `hide()` is held back so the up has something to land on.
    private var isConsumingClick = false
    private var hideDeferred = false
    /// Safety net: a mouse-up can genuinely never arrive (the system can steal the
    /// drag, or a Space/display change can interrupt it). Without a timeout the
    /// shield would stay up over the whole screen indefinitely, eating everything —
    /// far worse than the leak it's guarding against.
    private var consumeTimeout: Timer?

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

        shieldView.onClick = { [weak self] in
            self?.beginConsumingClick()
            onClick()
        }
        shieldView.onClickFinished = { [weak self] in self?.endConsumingClick() }
        contentView = shieldView
    }

    private func beginConsumingClick() {
        isConsumingClick = true
        hideDeferred = false
        consumeTimeout?.invalidate()
        consumeTimeout = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.endConsumingClick() }
        }
    }

    private func endConsumingClick() {
        guard isConsumingClick else { return }
        consumeTimeout?.invalidate()
        consumeTimeout = nil
        isConsumingClick = false
        if hideDeferred {
            hideDeferred = false
            orderOut(nil)
        }
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

    /// Take the shield down, unless it's mid-click — in which case it stays until the
    /// mouse-up it still owes a home to.
    func hide() {
        guard !isConsumingClick else {
            hideDeferred = true
            return
        }
        orderOut(nil)
    }

    /// Stand down because the shield itself consumed the dismissing click. Same as
    /// `hide()`, named for the caller's intent — the deferral is the whole point here,
    /// since this is always called from inside the mouse-down.
    func dismiss() {
        hide()
    }
}
