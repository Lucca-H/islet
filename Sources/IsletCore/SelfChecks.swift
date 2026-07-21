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
        let a = NowPlayingInfo(title: "Song", artist: "Artist", album: "Album", isPlaying: true, sourceName: "Chrome")
        let b = NowPlayingInfo(title: "Song", artist: "Artist", album: "Album", isPlaying: true, sourceName: "Chrome")
        let c = NowPlayingInfo(title: "Other", artist: "Artist", album: "Album", isPlaying: true, sourceName: "Chrome")
        check(a == b, "identical now-playing snapshots are equal")
        check(a != c, "different titles are unequal")
    }

    print("MediaRemoteBridge")
    do {
        check(MediaRemoteBridge.shared.isAvailable, "MediaRemote framework symbols resolved")
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
        store.resetToDefaults()
        check(store.expandedWidth == 640, "reset restores expandedWidth")
        check(store.clipboardLimit == 50, "reset restores clipboardLimit")
        check(store.nowPlayingEnabled, "reset restores nowPlayingEnabled")
    }

    print(failures == 0 ? "\nAll checks passed ✅" : "\n\(failures) check(s) failed ❌")
    return failures
}
