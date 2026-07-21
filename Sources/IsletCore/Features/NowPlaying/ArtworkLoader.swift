import AppKit
import Foundation

/// Runs AppleScript out-of-process via `osascript`.
///
/// Kept out-of-process deliberately: `NSAppleScript` must run on the main thread and
/// blocks it, which would stutter the notch animations.
enum AppleScriptRunner {
    @discardableResult
    static func run(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

/// Fetches cover art for the currently playing track.
enum ArtworkLoader {
    static func fetch(for app: MediaApp) -> NSImage? {
        switch app {
        case .spotify: return fetchSpotify()
        case .music:   return fetchMusic()
        }
    }

    /// Spotify exposes an artwork URL, so just download it.
    private static func fetchSpotify() -> NSImage? {
        let script = """
        if application "Spotify" is running then
            tell application "Spotify"
                try
                    return artwork url of current track
                on error
                    return ""
                end try
            end tell
        end if
        return ""
        """
        guard
            let raw = AppleScriptRunner.run(script)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty, let url = URL(string: raw),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return NSImage(data: data)
    }

    /// Music only exposes artwork as raw bytes, which don't survive a round trip
    /// through `osascript` stdout — so have AppleScript write them to a temp file
    /// and read that back.
    private static func fetchMusic() -> NSImage? {
        let path = NSTemporaryDirectory().appending("islet-artwork.dat")
        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        if application "Music" is running then
            tell application "Music"
                try
                    if (count of artworks of current track) is 0 then return ""
                    set artData to raw data of artwork 1 of current track
                on error
                    return ""
                end try
            end tell
            try
                set f to open for access POSIX file "\(escaped)" with write permission
                set eof f to 0
                write artData to f
                close access f
                return "ok"
            on error
                try
                    close access POSIX file "\(escaped)"
                end try
                return ""
            end try
        end if
        return ""
        """
        guard AppleScriptRunner.run(script)?.contains("ok") == true else { return nil }
        defer { try? FileManager.default.removeItem(atPath: path) }
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return NSImage(data: data)
    }
}
