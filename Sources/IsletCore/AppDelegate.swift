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

    private var mouseMonitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()

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

        // Auto-peek the notch when a new track starts playing.
        nowPlaying.playbackStarted
            .sink { [weak self] _ in self?.pulseNowPlaying() }
            .store(in: &cancellables)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }
    }

    // MARK: - Controllers

    private func rebuildControllers() {
        controllers.forEach { $0.teardown() }
        controllers.removeAll()

        for screen in ScreenNotch.targetScreens(for: settings.screenTargeting) {
            let geometry = ScreenNotch.geometry(for: screen)
            let viewModel = NotchViewModel(settings: settings,
                                           nowPlaying: nowPlaying,
                                           shelf: shelf,
                                           clipboard: clipboard)
            controllers.append(NotchController(geometry: geometry, viewModel: viewModel))
        }
    }

    // MARK: - Feature lifecycle

    private func applyFeatureState() {
        if settings.nowPlayingEnabled { nowPlaying.start() } else { nowPlaying.stop() }
        if settings.clipboardEnabled { clipboard.start() } else { clipboard.stop() }
    }

    /// Briefly open the Now Playing tab on the primary notch when a track starts.
    private func pulseNowPlaying() {
        guard settings.nowPlayingEnabled, let primary = controllers.first else { return }
        primary.viewModel.selectedTab = .nowPlaying
        primary.viewModel.open()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak primary] in
            guard let primary, !primary.viewModel.isHovering else { return }
            primary.viewModel.close()
        }
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
    }
}
