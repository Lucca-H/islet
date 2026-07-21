import AppKit
import Combine
import os

/// A snapshot of what's currently playing.
struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var source: Source
    var artworkURL: URL?

    enum Source: String {
        case spotify = "Spotify"
        case music = "Music"

        var bundleID: String {
            switch self {
            case .spotify: return "com.spotify.client"
            case .music:   return "com.apple.Music"
            }
        }
    }
}

/// Detects and controls audio playback from Spotify and Apple Music.
///
/// Uses AppleScript (via `osascript`) to poll the currently-playing track of any
/// running supported player. This avoids the private MediaRemote framework, which
/// Apple gated behind a private entitlement in recent macOS releases, so third-party
/// apps can no longer read the system-wide Now Playing feed reliably.
@MainActor
final class NowPlayingManager: ObservableObject {
    @Published private(set) var info: NowPlayingInfo?
    @Published private(set) var artwork: NSImage?

    private let log = Logger(subsystem: "com.dynamicisland.islet", category: "NowPlaying")
    private var timer: Timer?
    private var lastArtworkURL: URL?
    private var isEnabled = false

    /// Emits when playback *starts* after being stopped — used to auto-peek the notch.
    let playbackStarted = PassthroughSubject<NowPlayingInfo, Never>()

    func start() {
        guard !isEnabled else { return }
        isEnabled = true
        poll()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        isEnabled = false
        timer?.invalidate()
        timer = nil
        info = nil
        artwork = nil
    }

    // MARK: - Transport controls

    func togglePlayPause() { runControl("playpause") }
    func nextTrack()       { runControl("next track") }
    func previousTrack()   { runControl("previous track") }

    private func runControl(_ command: String) {
        guard let source = info?.source ?? runningSource() else { return }
        let script = "tell application \"\(source.rawValue)\" to \(command)"
        Task.detached { Self.runOSA(script) }
        // Refresh shortly after so UI reflects the new state.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.poll() }
    }

    // MARK: - Polling

    private func runningSource() -> NowPlayingInfo.Source? {
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        if running.contains(NowPlayingInfo.Source.spotify.bundleID) { return .spotify }
        if running.contains(NowPlayingInfo.Source.music.bundleID) { return .music }
        return nil
    }

    private func poll() {
        guard isEnabled else { return }
        guard let source = runningSource() else {
            update(nil)
            return
        }
        Task.detached { [weak self] in
            let info = Self.fetch(source: source)
            guard let self else { return }
            await self.update(info)
        }
    }

    private func update(_ new: NowPlayingInfo?) {
        let wasPlaying = info?.isPlaying ?? false
        if info != new {
            let previous = info
            info = new
            if let new, new.isPlaying, !wasPlaying || previous?.title != new.title {
                playbackStarted.send(new)
            }
        }
        loadArtworkIfNeeded()
    }

    private func loadArtworkIfNeeded() {
        guard let url = info?.artworkURL else {
            if info == nil { artwork = nil; lastArtworkURL = nil }
            return
        }
        guard url != lastArtworkURL else { return }
        lastArtworkURL = url
        Task.detached { [weak self] in
            guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return }
            guard let self else { return }
            await self.applyArtwork(image)
        }
    }

    private func applyArtwork(_ image: NSImage) {
        artwork = image
    }

    // MARK: - AppleScript bridges

    private nonisolated static func fetch(source: NowPlayingInfo.Source) -> NowPlayingInfo? {
        let sep = "\u{001F}" // unit separator, unlikely to appear in metadata
        let script: String
        switch source {
        case .spotify:
            script = """
            tell application "Spotify"
                if it is running then
                    set st to (player state as text)
                    if st is "stopped" then return ""
                    set t to name of current track
                    set a to artist of current track
                    set al to album of current track
                    set art to artwork url of current track
                    return t & "\(sep)" & a & "\(sep)" & al & "\(sep)" & st & "\(sep)" & art
                end if
            end tell
            return ""
            """
        case .music:
            script = """
            tell application "Music"
                if it is running then
                    set st to (player state as text)
                    if st is "stopped" then return ""
                    set t to name of current track
                    set a to artist of current track
                    set al to album of current track
                    return t & "\(sep)" & a & "\(sep)" & al & "\(sep)" & st & "\(sep)"
                end if
            end tell
            return ""
            """
        }

        guard let output = runOSA(script)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else { return nil }

        let parts = output.components(separatedBy: sep)
        guard parts.count >= 4 else { return nil }
        let state = parts[3].lowercased()
        let artworkURL = parts.count >= 5 ? URL(string: parts[4]) : nil

        return NowPlayingInfo(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            isPlaying: state == "playing",
            source: source,
            artworkURL: artworkURL
        )
    }

    @discardableResult
    private nonisolated static func runOSA(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
