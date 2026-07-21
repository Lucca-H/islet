import AppKit
import SwiftUI

/// A tiny built-in assertion harness so the core logic can be verified without
/// XCTest or swift-testing (neither ships with Command Line Tools). Mirrors the
/// swift-testing suite in `Tests/` so both cover the same ground.
///
/// Returns the number of failed checks (0 means everything passed).
@MainActor
public func runIsletSelfChecks() -> Int {
    var failures = 0
    func check(_ condition: Bool, _ label: String) {
        if condition {
            print("  ✓ \(label)")
        } else {
            failures += 1
            print("  ✗ \(label)")
        }
    }

    print("NotchShape")
    do {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 120)
        let path = NotchShape(bottomRadius: 20, topRadius: 10).path(in: rect)
        check(!path.isEmpty, "produces a non-empty path")
        check(rect.insetBy(dx: -1, dy: -1).contains(path.boundingRect), "stays within bounds")

        let clamped = NotchShape(bottomRadius: 9999, topRadius: 9999).path(in: CGRect(x: 0, y: 0, width: 50, height: 40))
        check(!clamped.isEmpty, "clamps oversized radii to a valid path")
    }

    print("Enums")
    do {
        check(ExpandTrigger.allCases.allSatisfy { ExpandTrigger(rawValue: $0.rawValue) == $0 }, "ExpandTrigger round-trips")
        check(ScreenTargeting.allCases.allSatisfy { ScreenTargeting(rawValue: $0.rawValue) == $0 }, "ScreenTargeting round-trips")
        check(NotchTab.allCases.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty }, "every tab has a title and symbol")
    }

    print("NowPlayingInfo")
    do {
        func make(_ title: String) -> NowPlayingInfo {
            NowPlayingInfo(title: title, artist: "Artist", album: "Album", isPlaying: true,
                           sourceName: "Music", sourceBundleID: "com.apple.Music")
        }
        check(make("Song") == make("Song"), "identical now-playing snapshots are equal")
        check(make("Song") != make("Other"), "different titles are unequal")
        check(make("Song").trackKey != make("Other").trackKey, "track keys differ per track")
    }

    print("MediaApp")
    do {
        check(MediaApp.music.bundleID == "com.apple.Music", "Music bundle id")
        check(MediaApp.spotify.bundleID == "com.spotify.client", "Spotify bundle id")
        check(MediaApp.music.notificationName.rawValue == "com.apple.iTunes.playerInfo",
              "Music posts the iTunes playerInfo notification")
        check(MediaApp.spotify.notificationName.rawValue == "com.spotify.client.PlaybackStateChanged",
              "Spotify posts its PlaybackStateChanged notification")
        // Regression guard: AppleScript parses short names like `st` as the ordinal
        // "1st" and raises a syntax error, which silently broke all metadata queries.
        for app in MediaApp.allCases {
            let script = app.metadataScript(separator: "|")
            check(script.contains("is running"), "\(app.rawValue) script guards on `is running` so it never launches the app")
            check(!script.contains("set st to"), "\(app.rawValue) script avoids AppleScript-reserved short names")
        }
    }

    print("NotchPeek")
    do {
        let peek = NotchPeek.fileAdded(name: "report.pdf")
        check(peek.text == "Added report.pdf", "fileAdded formats its text")
        check(!peek.symbol.isEmpty, "every peek kind has a symbol")
    }

    print("ClipItem")
    do {
        check(ClipItem.Kind.text("hello") == ClipItem.Kind.text("hello"), "identical text is equal")
        check(ClipItem.Kind.text("hello") != ClipItem.Kind.text("world"), "different text is unequal")
        let image = NSImage(size: NSSize(width: 2, height: 2))
        check(ClipItem.Kind.text("x") != ClipItem.Kind.image(image), "text and image are unequal")
    }

    print("SettingsStore")
    do {
        let store = SettingsStore.shared
        store.expandedWidth = 800
        store.clipboardLimit = 5
        store.nowPlayingEnabled = false
        store.notchMaterial = .solid
        store.resetToDefaults()
        check(store.expandedWidth == 640, "reset restores expandedWidth")
        check(store.clipboardLimit == 50, "reset restores clipboardLimit")
        check(store.nowPlayingEnabled, "reset restores nowPlayingEnabled")
        check(store.notchMaterial == .liquidGlass, "reset restores notchMaterial")
        check(NotchMaterial.allCases.allSatisfy { NotchMaterial(rawValue: $0.rawValue) == $0 }, "NotchMaterial round-trips")
    }

    print(failures == 0 ? "\nAll checks passed ✅" : "\n\(failures) check(s) failed ❌")
    return failures
}
