import AppKit
import Combine
import os

/// A snapshot of what's currently playing.
struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var sourceName: String
    var sourceBundleID: String

    /// Identity of the *track* (ignoring play/pause) — used to decide when artwork
    /// must be refetched.
    var trackKey: String { "\(sourceBundleID)|\(title)|\(album)|\(artist)" }
}

/// Detects and controls media playback.
///
/// Primary feed is `DistributedNotificationCenter`: Music and Spotify each post a
/// notification carrying full metadata on every playback change. That is push-based,
/// instant, needs no entitlement, and triggers no permission prompt.
///
/// AppleScript fills the gaps the notification feed can't cover — reading state at
/// launch (notifications only fire on *change*), fetching artwork, and sending
/// transport commands. Those do require Automation permission, so metadata keeps
/// working even if the user declines it.
///
/// `MediaRemoteBridge` is tried first when available: it would additionally cover
/// browser/web audio. On macOS 26 it returns nothing unless the caller is an
/// Apple-signed binary, so in practice it self-disables after a few empty replies.
@MainActor
final class NowPlayingManager: ObservableObject {
    @Published private(set) var info: NowPlayingInfo?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var sourceIcon: NSImage?

    private let log = Logger(subsystem: "com.dynamicisland.islet", category: "NowPlaying")
    private let bridge = MediaRemoteBridge.shared
    private let separator = "\u{001F}"

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var isEnabled = false

    /// MediaRemote is gated to Apple-signed callers; stop asking after this many
    /// consecutive empty replies so we don't burn a round-trip every refresh.
    private var mediaRemoteEmptyReplies = 0
    private var mediaRemoteUsable = true
    private static let mediaRemoteGiveUpThreshold = 3

    private var artworkTrackKey: String?

    /// When the notification feed last told us something. The AppleScript backup poll
    /// must not wipe that out — if Automation permission is denied the poll always
    /// comes back empty, and clearing on it would make Now Playing flicker away even
    /// though the (permission-free) notification feed is working fine.
    private var lastNotificationAt: Date?
    private static let notificationTrustWindow: TimeInterval = 20

    /// Emits when a new track starts playing — drives the subtle notch peek.
    let playbackStarted = PassthroughSubject<NowPlayingInfo, Never>()

    func start() {
        guard !isEnabled else { return }
        isEnabled = true

        let center = DistributedNotificationCenter.default()
        for app in MediaApp.allCases {
            let token = center.addObserver(forName: app.notificationName, object: nil, queue: .main) { [weak self] note in
                Task { @MainActor in self?.handleNotification(from: app, userInfo: note.userInfo) }
            }
            observers.append(token)
        }

        refresh()
        // Backup poll: catches state that changed while we weren't listening and
        // apps that stop posting notifications (e.g. quitting mid-track).
        let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        isEnabled = false
        timer?.invalidate()
        timer = nil
        let center = DistributedNotificationCenter.default()
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
        info = nil
        artwork = nil
        sourceIcon = nil
        artworkTrackKey = nil
    }

    // MARK: - Transport controls

    func togglePlayPause() { sendCommand("playpause") }
    func nextTrack()       { sendCommand("next track") }
    func previousTrack()   { sendCommand("previous track") }

    private func sendCommand(_ command: String) {
        // Prefer MediaRemote when it actually works (covers browsers too).
        if mediaRemoteUsable, bridge.isAvailable {
            let sent: Bool
            switch command {
            case "playpause":     sent = bridge.send(.togglePlayPause)
            case "next track":    sent = bridge.send(.nextTrack)
            default:              sent = bridge.send(.previousTrack)
            }
            if sent { scheduleRefresh(); return }
        }
        guard let app = activeApp else { return }
        let script = "if application \"\(app.rawValue)\" is running then tell application \"\(app.rawValue)\" to \(command)"
        Task.detached { _ = AppleScriptRunner.run(script) }
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refresh() }
    }

    /// The app whose playback we're currently showing, else the first running one.
    private var activeApp: MediaApp? {
        if let id = info?.sourceBundleID, let match = MediaApp.allCases.first(where: { $0.bundleID == id }) {
            return match
        }
        return MediaApp.allCases.first(where: { $0.isRunning })
    }

    // MARK: - Notification feed

    private func handleNotification(from app: MediaApp, userInfo: [AnyHashable: Any]?) {
        guard isEnabled, let userInfo else { return }
        let state = (userInfo["Player State"] as? String ?? "").lowercased()
        guard state != "stopped" else {
            if info?.sourceBundleID == app.bundleID { apply(nil) }
            return
        }
        guard let title = userInfo["Name"] as? String, !title.isEmpty else { return }

        let new = NowPlayingInfo(
            title: title,
            artist: userInfo["Artist"] as? String ?? "",
            album: userInfo["Album"] as? String ?? "",
            isPlaying: state == "playing",
            sourceName: app.rawValue,
            sourceBundleID: app.bundleID
        )
        // Don't let a paused app override another app that's actively playing.
        if !new.isPlaying, let current = info, current.isPlaying, current.sourceBundleID != app.bundleID { return }
        lastNotificationAt = Date()
        apply(new)
    }

    /// True while the notification feed is recent enough to outrank an empty poll.
    private var notificationFeedIsFresh: Bool {
        guard let lastNotificationAt else { return false }
        return Date().timeIntervalSince(lastNotificationAt) < Self.notificationTrustWindow
    }

    // MARK: - Refresh (MediaRemote → AppleScript)

    private func refresh() {
        guard isEnabled else { return }

        if mediaRemoteUsable, bridge.isAvailable {
            bridge.fetchSnapshot { [weak self] snapshot in
                DispatchQueue.main.async {
                    guard let self, self.isEnabled else { return }
                    if let snapshot {
                        self.mediaRemoteEmptyReplies = 0
                        self.apply(NowPlayingInfo(
                            title: snapshot.title, artist: snapshot.artist, album: snapshot.album,
                            isPlaying: snapshot.isPlaying,
                            sourceName: snapshot.sourceName ?? "Now Playing",
                            sourceBundleID: snapshot.sourceBundleID ?? ""
                        ), directArtwork: snapshot.artworkData)
                    } else {
                        self.mediaRemoteEmptyReplies += 1
                        if self.mediaRemoteEmptyReplies >= Self.mediaRemoteGiveUpThreshold {
                            self.mediaRemoteUsable = false
                            self.log.info("MediaRemote returned no data; using the scriptable-app feed instead.")
                        }
                        self.refreshFromScriptableApps()
                    }
                }
            }
        } else {
            refreshFromScriptableApps()
        }
    }

    private func refreshFromScriptableApps() {
        let running = MediaApp.allCases.filter(\.isRunning)
        guard !running.isEmpty else { apply(nil); return }
        let separator = self.separator

        Task.detached { [weak self] in
            var best: NowPlayingInfo?
            for app in running {
                guard let output = AppleScriptRunner.run(app.metadataScript(separator: separator))?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else { continue }
                let parts = output.components(separatedBy: separator)
                guard parts.count >= 4 else { continue }
                let candidate = NowPlayingInfo(
                    title: parts[0], artist: parts[1], album: parts[2],
                    isPlaying: parts[3].lowercased() == "playing",
                    sourceName: app.rawValue, sourceBundleID: app.bundleID
                )
                // A playing app always wins over a paused one.
                if candidate.isPlaying { best = candidate; break }
                if best == nil { best = candidate }
            }
            let result = best
            guard let self else { return }
            await self.applyPolled(result)
        }
    }

    /// Apply a poll result. An empty poll never clears state the notification feed just
    /// supplied (the likeliest cause of an empty poll is denied Automation permission).
    private func applyPolled(_ result: NowPlayingInfo?) {
        if result == nil, notificationFeedIsFresh { return }
        apply(result)
    }

    // MARK: - Applying state

    private func apply(_ new: NowPlayingInfo?, directArtwork: Data? = nil) {
        let wasPlaying = info?.isPlaying ?? false
        let previousKey = info?.trackKey

        if info != new {
            info = new
            if let new, new.isPlaying, !wasPlaying || previousKey != new.trackKey {
                playbackStarted.send(new)
            }
        }

        guard let new else {
            artwork = nil
            sourceIcon = nil
            artworkTrackKey = nil
            return
        }

        sourceIcon = MediaApp.allCases.first(where: { $0.bundleID == new.sourceBundleID })?
            .runningApplication?.icon

        guard artworkTrackKey != new.trackKey else { return }
        artworkTrackKey = new.trackKey

        if let directArtwork, let image = NSImage(data: directArtwork) {
            artwork = image
            return
        }
        artwork = nil
        loadArtwork(for: new)
    }

    private func loadArtwork(for target: NowPlayingInfo) {
        guard let app = MediaApp.allCases.first(where: { $0.bundleID == target.sourceBundleID }) else { return }
        let key = target.trackKey

        Task.detached { [weak self] in
            let image = ArtworkLoader.fetch(for: app)
            guard let self else { return }
            await self.applyArtwork(image, forTrackKey: key)
        }
    }

    /// Ignore artwork that arrived after the track already changed.
    private func applyArtwork(_ image: NSImage?, forTrackKey key: String) {
        guard artworkTrackKey == key else { return }
        artwork = image
    }
}
