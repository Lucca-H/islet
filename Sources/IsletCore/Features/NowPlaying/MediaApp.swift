import AppKit

/// A scriptable media player Islet can observe and control.
///
/// Both Music and Spotify broadcast a `DistributedNotificationCenter` notification
/// on every playback change, carrying full track metadata in `userInfo`. That feed
/// needs no entitlement and no permission prompt, which makes it the backbone of
/// Now Playing detection.
enum MediaApp: String, CaseIterable {
    case music = "Music"
    case spotify = "Spotify"

    var bundleID: String {
        switch self {
        case .music:   return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }

    /// The distributed notification this app posts when playback changes.
    var notificationName: Notification.Name {
        switch self {
        case .music:   return Notification.Name("com.apple.iTunes.playerInfo")
        case .spotify: return Notification.Name("com.spotify.client.PlaybackStateChanged")
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    var runningApplication: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    /// Whether `duration of current track` comes back in milliseconds.
    ///
    /// Spotify reports milliseconds and Music reports seconds, for the same property
    /// name — reading both as one unit puts the progress bar out by a factor of 1000.
    var durationIsMilliseconds: Bool { self == .spotify }

    /// AppleScript that returns the current track as unit-separated fields, or an
    /// empty string when stopped. Guarded by `is running` so it never launches the app.
    ///
    /// Variable names are spelled out deliberately: short ones like `st` are parsed as
    /// ordinal suffixes ("1st") by AppleScript and raise a syntax error.
    func metadataScript(separator: String) -> String {
        let artwork = self == .spotify
            ? "set theArt to artwork url of current track"
            : "set theArt to \"\""
        return """
        if application "\(rawValue)" is running then
            tell application "\(rawValue)"
                try
                    set theState to (player state as text)
                    if theState is "stopped" then return ""
                    set theTitle to name of current track
                    set theArtist to artist of current track
                    set theAlbum to album of current track
                    \(artwork)
                    -- Position and duration are read in their own try block: a track
                    -- can legitimately report neither (streams, some local files), and
                    -- letting that fail would throw away the metadata above with it.
                    set thePosition to 0
                    set theDuration to 0
                    try
                        set thePosition to player position
                        set theDuration to duration of current track
                    end try
                    return theTitle & "\(separator)" & theArtist & "\(separator)" & theAlbum & "\(separator)" & theState & "\(separator)" & theArt & "\(separator)" & (thePosition as text) & "\(separator)" & (theDuration as text)
                on error
                    return ""
                end try
            end tell
        end if
        return ""
        """
    }
}
