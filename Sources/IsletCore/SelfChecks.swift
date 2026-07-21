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

    print("NotchGeometry")
    do {
        // Regression guard: content drawn exactly within the true camera-cutout
        // width is physically invisible (that region has no real pixels), so the
        // collapsed pill must always be wider than the bare notch on real hardware.
        let physical = NotchGeometry(screen: NSScreen.main ?? NSScreen.screens[0],
                                     notchRect: CGRect(x: 0, y: 0, width: 200, height: 32),
                                     hasPhysicalNotch: true)
        check(physical.collapsedContentWidth > physical.notchWidth,
              "collapsed pill is wider than the true notch cutout on real hardware")
        check(physical.contentSafeMargin > 0, "real hardware gets a nonzero content margin")

        let virtual = NotchGeometry(screen: NSScreen.main ?? NSScreen.screens[0],
                                    notchRect: CGRect(x: 0, y: 0, width: 220, height: 32),
                                    hasPhysicalNotch: false)
        check(virtual.collapsedContentWidth == virtual.notchWidth,
              "no extra margin on notchless (virtual) displays — already real pixels")
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

    print("QuickNoteManager")
    do {
        let defaults = UserDefaults(suiteName: "com.dynamicisland.islet.selfchecks.quicknote")!
        defaults.removePersistentDomain(forName: "com.dynamicisland.islet.selfchecks.quicknote")
        let manager = QuickNoteManager(defaults: defaults)
        check(manager.text.isEmpty, "starts empty with no prior saved note")
        check(manager.lastEditedAt == nil, "no edit timestamp before any edit")
        manager.text = "buy milk"
        check(manager.lastEditedAt != nil, "editing sets a timestamp")
        manager.clear()
        check(manager.text.isEmpty, "clear empties the note")
    }

    print("NotchTab")
    do {
        check(NotchTab.allCases.contains(.quickNote), "Quick Note is a real tab")
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
        store.audioVisualizerEnabled = true
        store.quickNoteEnabled = false
        store.resetToDefaults()
        check(store.expandedWidth == 640, "reset restores expandedWidth")
        check(store.clipboardLimit == 50, "reset restores clipboardLimit")
        check(store.nowPlayingEnabled, "reset restores nowPlayingEnabled")
        check(store.notchMaterial == .liquidGlass, "reset restores notchMaterial")
        check(store.quickNoteEnabled, "reset restores quickNoteEnabled")
        check(NotchMaterial.allCases.allSatisfy { NotchMaterial(rawValue: $0.rawValue) == $0 }, "NotchMaterial round-trips")
        check(!store.audioVisualizerEnabled, "reset restores audioVisualizerEnabled to off (needs explicit opt-in)")
    }

    print("AudioVisualizerEngine")
    do {
        check(AudioVisualizerEngine.bandCount == 4, "bandCount matches the UI's expected bar count")
        let engine = AudioVisualizerEngine.shared
        check(engine.bars.count == AudioVisualizerEngine.bandCount, "starts with one level per band")
        check(!engine.isCapturing, "not capturing until explicitly started")
    }

    print(failures == 0 ? "\nAll checks passed ✅" : "\n\(failures) check(s) failed ❌")
    return failures
}
