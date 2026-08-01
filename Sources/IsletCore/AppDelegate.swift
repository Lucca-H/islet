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
    private let audioVisualizer = AudioVisualizerEngine.shared
    private lazy var quickNote = QuickNoteManager()

    private var statusBar: StatusBarController?
    private var controllers: [NotchController] = []
    private lazy var clickShield = ClickShieldWindow { [weak self] in self?.dismissOnOutsideClick() }

    private var mouseMonitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var audioVisualizerRetryTimer: Timer?

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
            .sink { [weak self] _ in
                self?.applyFeatureState()
                // Whether the shield belongs up at all depends on `expandTrigger`,
                // so switching hover/click has to re-evaluate it, not just wait for
                // the next expand.
                self?.updateClickShield()
            }
            .store(in: &cancellables)

        // Capture system audio only while both the setting is on and something is
        // actually playing — never idly, so the system recording indicator isn't
        // up any longer than it has to be.
        nowPlaying.$info
            .map { $0?.isPlaying ?? false }
            .removeDuplicates()
            // The mapped value is passed through rather than discarded: `@Published`
            // emits in `willSet`, so re-reading `nowPlaying.info` inside the sink
            // still returns the *previous* value. Doing that meant the gate below saw
            // "not playing" at the exact moment playback started, so capture was
            // never begun — the visualizer stayed dark no matter what.
            .sink { [weak self] isPlaying in
                self?.updateAudioVisualizerState(isPlayingOverride: isPlaying)
            }
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
                                           clipboard: clipboard,
                                           audioVisualizer: audioVisualizer,
                                           quickNote: quickNote)
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

    /// The shield goes up only when a click is genuinely how the notch gets
    /// dismissed — that is, in **click** trigger mode while something is open.
    ///
    /// In hover mode it was actively harmful. The notch dismisses itself when the
    /// pointer leaves, but not instantly: `hoverCloseDelay` (0.35s by default) keeps
    /// it expanded for a moment afterward, and the shield spans every screen for that
    /// whole window. Moving off the notch and clicking something straight away — an
    /// entirely normal thing to do, and fast enough to beat 350ms — meant the click
    /// hit the shield instead of its target and was swallowed for a dismissal the
    /// user had already accomplished by moving away. There is no dismissing click to
    /// consume in hover mode, so there is nothing for the shield to do there.
    private func updateClickShield() {
        let dismissedByClicking = settings.expandTrigger == .click
        if dismissedByClicking && controllers.contains(where: { $0.viewModel.isExpanded }) {
            clickShield.show()
        } else {
            clickShield.hide()
        }
    }

    /// The shield absorbed a click: collapse and get out of the way, so the user's
    /// *next* click reaches whatever they were aiming at.
    ///
    /// `dismiss()` rather than `hide()` because the shield has only seen the mouse
    /// **down** at this point. Ordering out here left the matching mouse-up to land
    /// on whatever was underneath, so the click was only half-swallowed.
    private func dismissOnOutsideClick() {
        clickShield.dismiss()
        controllers.forEach { $0.viewModel.clickedOutside() }
    }

    // MARK: - Feature lifecycle

    private func applyFeatureState() {
        if settings.nowPlayingEnabled { nowPlaying.start() } else { nowPlaying.stop() }
        if settings.clipboardEnabled { clipboard.start() } else { clipboard.stop() }
        updateAudioVisualizerState()
    }

    /// Capture only while a tracked player is actually playing.
    ///
    /// This gate was briefly removed while Islet still tried to cover browser audio —
    /// back then it wrongly switched the visualizer off for the one source only
    /// ScreenCaptureKit could see. Now that Now Playing is deliberately Music/Spotify
    /// only, tying capture to real playback is both correct and better behaved: the
    /// screen-recording indicator stays off whenever music isn't playing, instead of
    /// for the entire time the feature is enabled.
    ///
    /// `AudioVisualizerEngine.start()` silently no-ops if permission isn't granted
    /// yet — and nothing was ever calling it *again*. If the toggle was already on
    /// from a previous session, `applyFeatureState()` tries once at launch; if
    /// permission is granted afterward (the normal flow: launch, notice it's dark,
    /// go grant it in System Settings), that one attempt already failed and nothing
    /// retried. `retryTimer` keeps trying at a low rate until it actually succeeds.
    /// - Parameter isPlayingOverride: supplied by the `$info` subscription, whose
    ///   `willSet`-timed emission means the stored property is still stale when the
    ///   sink runs. Callers outside that subscription can omit it and read live state.
    private func updateAudioVisualizerState(isPlayingOverride: Bool? = nil) {
        let isPlaying = isPlayingOverride ?? (nowPlaying.info?.isPlaying ?? false)
        let shouldRun = settings.audioVisualizerEnabled
            && settings.nowPlayingEnabled
            && isPlaying
        // Follow whichever player Now Playing resolved, so the bars describe the track
        // shown beside them rather than the whole system mix (a video in a browser
        // playing over Spotify was being summed into the same FFT). Set before
        // start() so the first stream is already scoped; changing it while running
        // restarts capture, since a content filter is fixed per stream.
        audioVisualizer.setCaptureSource(bundleIdentifier: nowPlaying.info?.sourceBundleID)
        if shouldRun {
            audioVisualizer.start()
            startAudioVisualizerRetryLoopIfNeeded()
        } else {
            audioVisualizer.stop()
            audioVisualizerRetryTimer?.invalidate()
            audioVisualizerRetryTimer = nil
        }
    }

    /// Runs for as long as capture *should* be running — idling while it actually is,
    /// rather than tearing itself down on first success.
    ///
    /// It previously invalidated itself the moment `isCapturing` became true, which
    /// left a hole: if the engine's watchdog later caught a stalled stream and its
    /// `stop()`/`start()` restart failed (permission dropped, no display, etc.), the
    /// engine's own timer was already gone with `stop()` and this loop had retired —
    /// so nothing retried, and the visualizer stayed dead until playback state
    /// happened to change. An idle tick every 2s is far cheaper than reintroducing
    /// the silent-death bug this whole mechanism exists to prevent.
    private func startAudioVisualizerRetryLoopIfNeeded() {
        guard audioVisualizerRetryTimer == nil else { return }
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Only `shouldRun` going false retires the loop — handled by
                // updateAudioVisualizerState, which invalidates it directly.
                guard self.settings.audioVisualizerEnabled, self.settings.nowPlayingEnabled else { return }
                guard !self.audioVisualizer.isCapturing else { return }
                self.audioVisualizer.start()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        audioVisualizerRetryTimer = timer
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
