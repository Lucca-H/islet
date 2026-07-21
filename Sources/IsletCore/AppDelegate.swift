import AppKit
import Combine

/// Wires the whole app together: shared feature managers, one notch controller per
/// target screen, the menu-bar item, and a global pointer monitor that drives
/// expand/collapse.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() { super.init() }

    private let settings = SettingsStore.shared
    private lazy var nowPlaying = NowPlayingManager()
    private lazy var shelf = DropShelfManager()
    private lazy var clipboard = ClipboardManager(settings: settings)

    private var statusBar: StatusBarController?
    private var controllers: [NotchController] = []
    private lazy var clickShield = ClickShieldWindow { [weak self] in self?.dismissOnOutsideClick() }

    private var mouseMonitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()

        rebuildControllers()
        installPointerMonitors()
        applyFeatureState()

        // Rebuild when displays are added/removed or rearranged.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildControllers() }
            .store(in: &cancellables)

        // React to feature toggles without a relaunch.
        settings.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.applyFeatureState() }
            .store(in: &cancellables)

        // Subtle live-activity peeks for background events — brief, low-key,
        // never a full expand.
        nowPlaying.playbackStarted
            .sink { [weak self] info in
                self?.peek(.nowPlaying(title: info.title, artist: info.artist))
            }
            .store(in: &cancellables)

        shelf.itemAdded
            .sink { [weak self] item in self?.peek(.fileAdded(name: item.name)) }
            .store(in: &cancellables)

        clipboard.itemCaptured
            .sink { [weak self] item in
                let preview: String
                switch item.kind {
                case let .text(value):
                    preview = "Copied: \(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))"
                case .image:
                    preview = "Copied an image"
                }
                self?.peek(.copied(preview: preview))
            }
            .store(in: &cancellables)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }
    }

    // MARK: - Controllers

    private func rebuildControllers() {
        controllers.forEach { $0.teardown() }
        controllers.removeAll()
        controllerCancellables.removeAll()

        for screen in ScreenNotch.targetScreens(for: settings.screenTargeting) {
            let geometry = ScreenNotch.geometry(for: screen)
            let viewModel = NotchViewModel(settings: settings,
                                           nowPlaying: nowPlaying,
                                           shelf: shelf,
                                           clipboard: clipboard)
            controllers.append(NotchController(geometry: geometry, viewModel: viewModel))

            // @Published fires in willSet, so read the settled state next tick.
            viewModel.$isExpanded
                .removeDuplicates()
                .sink { [weak self] _ in DispatchQueue.main.async { self?.updateClickShield() } }
                .store(in: &controllerCancellables)
        }

        updateClickShield()
    }

    // MARK: - Outside clicks

    /// The shield is only up while something is open, so it never eats a click
    /// the user meant for another app.
    private func updateClickShield() {
        if controllers.contains(where: { $0.viewModel.isExpanded }) {
            clickShield.show()
        } else {
            clickShield.hide()
        }
    }

    /// The shield absorbed a click: collapse now and get out of the way, so the
    /// user's next click reaches whatever they were aiming at.
    private func dismissOnOutsideClick() {
        clickShield.hide()
        controllers.forEach { $0.viewModel.clickedOutside() }
    }

    // MARK: - Feature lifecycle

    private func applyFeatureState() {
        if settings.nowPlayingEnabled { nowPlaying.start() } else { nowPlaying.stop() }
        if settings.clipboardEnabled { clipboard.start() } else { clipboard.stop() }
    }

    /// Show a subtle peek on the primary notch for a background event.
    private func peek(_ kind: NotchPeek) {
        controllers.first?.viewModel.showPeek(kind)
    }

    // MARK: - Pointer monitoring

    private func installPointerMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            guard let self else { return }
            let location = NSEvent.mouseLocation
            for controller in self.controllers { controller.handlePointer(at: location) }
        }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { handler($0) }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
            handler(event); return event
        }) {
            mouseMonitors.append(local)
        }

        // A click away from an open notch dismisses it immediately; without one,
        // the hover close delay stays in charge. The shield swallows outside
        // clicks itself — this also catches clicks landing on the notch window's
        // own transparent padding, which sits above the shield.
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let clickHandler: (NSEvent) -> Void = { [weak self] _ in
            guard let self else { return }
            let location = NSEvent.mouseLocation
            for controller in self.controllers { controller.handleClick(at: location) }
        }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { clickHandler($0) }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { event in
            clickHandler(event); return event
        }) {
            mouseMonitors.append(local)
        }
    }
}
