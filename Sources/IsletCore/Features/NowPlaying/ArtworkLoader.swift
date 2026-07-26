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

    /// Spotify exposes an artwork URL, so just download it — at the largest size it
    /// offers rather than whichever one AppleScript happened to hand back.
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
            !raw.isEmpty, let url = URL(string: raw)
        else { return nil }

        // Try the upgraded URL first, but never let a failed guess cost us the artwork
        // entirely — if Spotify ever changes its CDN scheme the rewrite could 404.
        if let upgraded = highestResolutionSpotifyURL(from: url),
           let data = try? Data(contentsOf: upgraded),
           let image = NSImage(data: data) {
            return normalizedToPixelSize(image)
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data).map(normalizedToPixelSize)
    }

    /// Rewrite a Spotify CDN image URL to its 640px variant.
    ///
    /// `artwork url of current track` usually returns the **300px** thumbnail, which is
    /// only just enough for the panel's ~132pt art on a 2x display and visibly soft on
    /// the larger size settings. Spotify encodes the dimension in the image ID itself —
    /// `ab67616d` followed by 8 hex digits identifying the size, then the album's own
    /// hash — so the large version is the same asset under a different prefix, no API
    /// call needed. Returns nil when the URL isn't in that recognised form, so an
    /// unfamiliar scheme falls back to the original rather than being mangled.
    static func highestResolutionSpotifyURL(from url: URL) -> URL? {
        let prefix = "ab67616d"
        let largeSize = "0000b273"   // 640x640
        let text = url.absoluteString

        guard let marker = text.range(of: prefix),
              let sizeEnd = text.index(marker.upperBound, offsetBy: 8, limitedBy: text.endIndex)
        else { return nil }

        let sizeField = marker.upperBound..<sizeEnd
        guard text[sizeField].allSatisfy(\.isHexDigit) else { return nil }
        guard text[sizeField] != largeSize else { return nil } // already the large variant

        return URL(string: text.replacingCharacters(in: sizeField, with: largeSize))
    }

    /// Make an `NSImage` report its size in *pixels* rather than in DPI-derived points.
    ///
    /// `NSImage(data:)` takes its `size` from the file's DPI metadata, so a 600px cover
    /// tagged at 144dpi reports a 300pt size. SwiftUI then treats that as the image's
    /// natural size and can draw it softer than the bitmap it actually holds. Restating
    /// the size as the real pixel dimensions costs nothing and keeps all the detail
    /// available to `.resizable()`.
    static func normalizedToPixelSize(_ image: NSImage) -> NSImage {
        let widest = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide })
        guard let rep = widest, rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return image }
        image.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        return image
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
        // Music hands over the full embedded artwork, so there's no larger version to
        // ask for — but it still needs its size restated in pixels.
        return NSImage(data: data).map(normalizedToPixelSize)
    }
}
