import Foundation
import AppKit
import os

/// A snapshot of the system's current Now Playing state.
struct MediaRemoteSnapshot {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var artworkData: Data?
    var sourceName: String?
    var sourceIcon: NSImage?
}

/// Transport commands understood by `MRMediaRemoteSendCommand`.
///
/// Raw values match the private `MRMediaRemoteCommand` enum — stable across many
/// years of third-party Now Playing widgets that rely on this same framework.
enum MediaRemoteCommand: Int {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case stop = 3
    case nextTrack = 4
    case previousTrack = 5
}

/// A thin bridge onto the private `MediaRemote.framework` — the same system
/// service that powers Control Center's Now Playing widget. It is loaded with
/// `dlopen`/`dlsym` at runtime rather than linked, since it is not a public SDK
/// framework.
///
/// This gives Islet **system-wide** now-playing info (any app that registers
/// media info, including Safari/Chrome tabs playing web audio — not just Music
/// and Spotify) plus the real embedded artwork bytes, which AppleScript cannot
/// provide. It is undocumented and could change in a future macOS release; every
/// call is guarded so a missing symbol degrades to "no data" rather than a crash.
final class MediaRemoteBridge {
    static let shared = MediaRemoteBridge()

    private let log = Logger(subsystem: "com.dynamicisland.islet", category: "MediaRemote")
    private let handle: UnsafeMutableRawPointer?

    private typealias GetNowPlayingInfoFunc =
        @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary) -> Void) -> Void
    private typealias GetPIDFunc =
        @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void
    private typealias SendCommandFunc =
        @convention(c) (Int, AnyObject?) -> Bool
    private typealias RegisterFunc =
        @convention(c) (DispatchQueue) -> Void

    private let getNowPlayingInfo: GetNowPlayingInfoFunc?
    private let getNowPlayingPID: GetPIDFunc?
    private let sendCommandFn: SendCommandFunc?
    private let registerForNotifications: RegisterFunc?

    /// Fires (on a background queue) whenever the system reports the now-playing
    /// state may have changed.
    var onChange: (() -> Void)?

    private let callbackQueue = DispatchQueue(label: "com.dynamicisland.islet.mediaremote")

    private init() {
        handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        guard let handle else {
            log.error("Could not load MediaRemote.framework")
            getNowPlayingInfo = nil
            getNowPlayingPID = nil
            sendCommandFn = nil
            registerForNotifications = nil
            return
        }

        getNowPlayingInfo = Self.symbol(handle, "MRMediaRemoteGetNowPlayingInfo")
        getNowPlayingPID = Self.symbol(handle, "MRMediaRemoteGetNowPlayingApplicationPID")
        sendCommandFn = Self.symbol(handle, "MRMediaRemoteSendCommand")
        registerForNotifications = Self.symbol(handle, "MRMediaRemoteRegisterForNowPlayingNotifications")

        registerForNotifications?(callbackQueue)
        for name in [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemotePlaybackQueueChangedNotification",
            "kMRNowPlayingPlaybackQueueChangedNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
        ] {
            NotificationCenter.default.addObserver(
                forName: Notification.Name(name), object: nil, queue: nil
            ) { [weak self] _ in self?.onChange?() }
        }
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T? {
        guard let ptr = dlsym(handle, name) else { return nil }
        return unsafeBitCast(ptr, to: T.self)
    }

    var isAvailable: Bool { getNowPlayingInfo != nil }

    func fetchSnapshot(completion: @escaping (MediaRemoteSnapshot?) -> Void) {
        guard let getNowPlayingInfo else { completion(nil); return }
        getNowPlayingInfo(callbackQueue) { [weak self] info in
            guard info.count > 0,
                  let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
                  !title.isEmpty
            else {
                completion(nil)
                return
            }
            let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            let album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
            let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
            let artwork = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data

            guard let self, let getPID = self.getNowPlayingPID else {
                completion(MediaRemoteSnapshot(title: title, artist: artist, album: album,
                                               isPlaying: rate > 0, artworkData: artwork,
                                               sourceName: nil, sourceIcon: nil))
                return
            }
            getPID(self.callbackQueue) { pid in
                var sourceName: String?
                var sourceIcon: NSImage?
                if pid > 0, let app = NSRunningApplication(processIdentifier: pid) {
                    sourceName = app.localizedName
                    sourceIcon = app.icon
                }
                completion(MediaRemoteSnapshot(
                    title: title, artist: artist, album: album,
                    isPlaying: rate > 0, artworkData: artwork,
                    sourceName: sourceName, sourceIcon: sourceIcon
                ))
            }
        }
    }

    @discardableResult
    func send(_ command: MediaRemoteCommand) -> Bool {
        sendCommandFn?(command.rawValue, nil) ?? false
    }
}
