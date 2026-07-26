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

/// Where playback is in the current track.
///
/// Holds the moment `elapsed` was measured rather than a live position, because the
/// source is a 3-second AppleScript poll — far too coarse to animate from directly.
/// `elapsed(at:)` extrapolates between samples, which is what makes a smooth bar out
/// of infrequent readings. Only extrapolates while playing; a paused track sits still.
struct PlaybackProgress: Equatable {
    var elapsed: TimeInterval
    var duration: TimeInterval
    var sampledAt: Date
    var isPlaying: Bool

    /// A duration of zero means the player didn't report one (streams, some local
    /// files). Callers should hide the bar rather than show a full or empty one.
    var isMeasurable: Bool { duration > 0 }

    func elapsed(at date: Date) -> TimeInterval {
        guard isPlaying else { return min(elapsed, duration) }
        return min(elapsed + date.timeIntervalSince(sampledAt), duration)
    }

    func fraction(at date: Date) -> Double {
        guard isMeasurable else { return 0 }
        return min(max(elapsed(at: date) / duration, 0), 1)
    }
}

/// Detects and controls playback in **Apple Music and Spotify**.
///
/// Primary feed is `DistributedNotificationCenter`: both apps post a notification
/// carrying full metadata on every playback change. That is push-based, instant,
/// needs no entitlement, and triggers no permission prompt.
///
/// AppleScript fills the gaps the notification feed can't cover — reading state at
/// launch (notifications only fire on *change*), fetching artwork, and sending
/// transport commands.
///
/// Browser/web audio is deliberately out of scope. The only system-wide API for it
/// (`MediaRemote`) is gated to Apple-signed callers on macOS 26 — verified directly,
/// it returns an empty dictionary for any third-party build — so supporting it was
/// never actually possible, and the dead private-API bridge has been removed rather
/// than left in pretending otherwise.
@MainActor
final class NowPlayingManager: ObservableObject {
    @Published private(set) var info: NowPlayingInfo?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var sourceIcon: NSImage?

    /// Playback position, kept **outside** `NowPlayingInfo` on purpose.
    ///
    /// `NowPlayingInfo` is `Equatable` and its equality drives real decisions — when
    /// `playbackStarted` fires, when artwork is refetched. A field that changes every
    /// few seconds by nature would make every poll look like a track change. It also
    /// isn't available on every path: the notification feed carries metadata but no
    /// reliable position, so it would have to be invented or cleared there.
    @Published private(set) var progress: PlaybackProgress?

    private let log = Logger(subsystem: "com.dynamicisland.islet", category: "NowPlaying")
    private let separator = "\u{001F}"

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var isEnabled = false

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
        progress = nil
    }

    // MARK: - Transport controls

    func togglePlayPause() { sendCommand("playpause") }
    func nextTrack()       { sendCommand("next track") }
    func previousTrack()   { sendCommand("previous track") }

    private func sendCommand(_ command: String) {
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
        // The feed carries no usable position, so pull one: this is the moment it
        // changed (track skip, seek, play/pause), and waiting up to 3s for the next
        // scheduled poll would leave the bar visibly stale exactly when it matters.
        scheduleRefresh()
    }

    /// True while the notification feed is recent enough to outrank an empty poll.
    private var notificationFeedIsFresh: Bool {
        guard let lastNotificationAt else { return false }
        return Date().timeIntervalSince(lastNotificationAt) < Self.notificationTrustWindow
    }

    // MARK: - Refresh

    private func refresh() {
        guard isEnabled else { return }
        refreshFromScriptableApps()
    }

    private func refreshFromScriptableApps() {
        let running = MediaApp.allCases.filter(\.isRunning)
        guard !running.isEmpty else { apply(nil); return }
        let separator = self.separator

        Task.detached { [weak self] in
            var best: NowPlayingInfo?
            var bestProgress: PlaybackProgress?
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
                // Older field layouts (and any app that couldn't report position) just
                // omit these, so read them defensively rather than widening the guard
                // above — losing the whole track because a stream has no duration
                // would be a much worse trade.
                let elapsed = parts.count > 5 ? Double(parts[5]) ?? 0 : 0
                let rawDuration = parts.count > 6 ? Double(parts[6]) ?? 0 : 0
                let duration = app.durationIsMilliseconds ? rawDuration / 1000 : rawDuration
                let progress = PlaybackProgress(elapsed: elapsed,
                                                duration: max(0, duration),
                                                sampledAt: Date(),
                                                isPlaying: candidate.isPlaying)

                // A playing app always wins over a paused one.
                if candidate.isPlaying {
                    best = candidate
                    bestProgress = progress
                    break
                }
                if best == nil {
                    best = candidate
                    bestProgress = progress
                }
            }
            let result = best
            let resultProgress = bestProgress
            guard let self else { return }
            await self.applyPolled(result, progress: resultProgress)
        }
    }

    /// Apply a poll result. An empty poll never clears state the notification feed just
    /// supplied (the likeliest cause of an empty poll is denied Automation permission).
    private func applyPolled(_ result: NowPlayingInfo?, progress newProgress: PlaybackProgress?) {
        if result == nil, notificationFeedIsFresh { return }
        apply(result)
        // Only after `apply`, which clears progress when playback stops.
        if result != nil { progress = newProgress }
    }

    // MARK: - Applying state

    private func apply(_ new: NowPlayingInfo?) {
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
            progress = nil
            return
        }

        // A new track invalidates the old position immediately — otherwise the bar
        // stays where the last track left it until the next 3s poll lands, which reads
        // as the new song starting halfway through.
        if previousKey != new.trackKey { progress = nil }

        sourceIcon = MediaApp.allCases.first(where: { $0.bundleID == new.sourceBundleID })?
            .runningApplication?.icon

        guard artworkTrackKey != new.trackKey else { return }
        artworkTrackKey = new.trackKey

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
