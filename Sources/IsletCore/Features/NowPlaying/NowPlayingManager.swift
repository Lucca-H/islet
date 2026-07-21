import AppKit
import Combine
import os

/// A snapshot of what's currently playing, from any app the system recognizes —
/// Music, Spotify, or a browser tab playing web audio.
struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var sourceName: String

    static func == (lhs: NowPlayingInfo, rhs: NowPlayingInfo) -> Bool {
        lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.album == rhs.album
            && lhs.isPlaying == rhs.isPlaying && lhs.sourceName == rhs.sourceName
    }
}

/// Detects and controls system-wide audio playback via the private `MediaRemote`
/// framework — the same feed behind Control Center's Now Playing widget. This
/// picks up Music, Spotify, and web audio playing in a browser tab (Safari,
/// Chrome, anything using the Media Session API), plus real embedded artwork.
@MainActor
final class NowPlayingManager: ObservableObject {
    @Published private(set) var info: NowPlayingInfo?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var sourceIcon: NSImage?

    private let log = Logger(subsystem: "com.dynamicisland.islet", category: "NowPlaying")
    private let bridge = MediaRemoteBridge.shared
    private var timer: Timer?
    private var isEnabled = false
    private var lastArtworkData: Data?

    /// Emits when playback *starts* after being stopped — used to auto-peek the notch.
    let playbackStarted = PassthroughSubject<NowPlayingInfo, Never>()

    func start() {
        guard !isEnabled else { return }
        isEnabled = true

        bridge.onChange = { [weak self] in
            DispatchQueue.main.async { self?.poll() }
        }

        poll()
        // Light polling backup in case a push notification is missed — MediaRemote
        // calls are cheap (no process spawn), so a short interval is fine.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        isEnabled = false
        bridge.onChange = nil
        timer?.invalidate()
        timer = nil
        info = nil
        artwork = nil
        sourceIcon = nil
        lastArtworkData = nil
    }

    // MARK: - Transport controls

    func togglePlayPause() { bridge.send(.togglePlayPause) }
    func nextTrack()       { bridge.send(.nextTrack) }
    func previousTrack()   { bridge.send(.previousTrack) }

    // MARK: - Polling

    private func poll() {
        guard isEnabled, bridge.isAvailable else { return }
        bridge.fetchSnapshot { [weak self] snapshot in
            DispatchQueue.main.async { self?.apply(snapshot) }
        }
    }

    private func apply(_ snapshot: MediaRemoteSnapshot?) {
        guard let snapshot else {
            update(nil)
            return
        }
        let new = NowPlayingInfo(
            title: snapshot.title, artist: snapshot.artist, album: snapshot.album,
            isPlaying: snapshot.isPlaying, sourceName: snapshot.sourceName ?? "Now Playing"
        )
        update(new)
        sourceIcon = snapshot.sourceIcon

        if let data = snapshot.artworkData, data != lastArtworkData {
            lastArtworkData = data
            artwork = NSImage(data: data)
        } else if snapshot.artworkData == nil {
            lastArtworkData = nil
            artwork = nil
        }
    }

    private func update(_ new: NowPlayingInfo?) {
        let wasPlaying = info?.isPlaying ?? false
        guard info != new else { return }
        let previous = info
        info = new
        if let new, new.isPlaying, !wasPlaying || previous?.title != new.title {
            playbackStarted.send(new)
        }
        if new == nil {
            artwork = nil
            sourceIcon = nil
            lastArtworkData = nil
        }
    }
}
