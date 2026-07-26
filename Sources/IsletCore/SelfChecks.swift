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
        // Regression guard: the expanded panel is far wider than the notch and
        // centered on it, so its top-center lands behind the camera housing. Content
        // must start below the band or the tab strip is invisible on real hardware.
        check(physical.contentTopInset == physical.notchHeight,
              "expanded/peek content is inset below the notch band on real hardware")

        let virtual = NotchGeometry(screen: NSScreen.main ?? NSScreen.screens[0],
                                    notchRect: CGRect(x: 0, y: 0, width: 220, height: 32),
                                    hasPhysicalNotch: false)
        check(virtual.collapsedContentWidth == virtual.notchWidth,
              "no extra margin on notchless (virtual) displays — already real pixels")
        check(virtual.contentTopInset == 0,
              "no top inset on notchless displays — nothing to dodge")

        // A sideways peek pins the edge it grows away from, so it shifts by exactly
        // half its extra width — and never shifts at all when it has none to add.
        check(physical.lateralPeekShift(peekWidth: physical.collapsedContentWidth + 200) == 100,
              "sideways peek shifts by half its extra width")
        check(physical.lateralPeekShift(peekWidth: physical.collapsedContentWidth) == 0,
              "a peek no wider than the pill doesn't move")
        check(physical.lateralPeekShift(peekWidth: 10) == 0,
              "a narrower-than-pill peek never shifts backwards")
        check(PeekDirection.left.lateralSign == -1 && PeekDirection.right.lateralSign == 1,
              "left and right peeks shift opposite ways")
        check(PeekDirection.down.lateralSign == 0 && !PeekDirection.down.isLateral,
              "a downward peek stays centered on the notch")
        // The window is only `expandedWidth` wide (plus shadow slack) and centered on
        // the notch, so a sideways pill has to stop before the window edge or it
        // clips against a rectangle instead of NotchShape. Symmetric, so checking the
        // leftward edge covers the rightward one.
        let limit = physical.maxLateralPeekWidth(expandedWidth: 640)
        let outerEdge = physical.lateralPeekShift(peekWidth: limit) + limit / 2
        check(outerEdge <= 320, "a sideways peek at its limit still fits inside the notch window")
        check(physical.peekLateralDeadWidth > physical.notchWidth,
              "sideways peek content clears the cutout and its flanking margin")

        // The peek opens as far as its text needs and no further, but a pathological
        // title must not be able to drag the pill past what the window can draw.
        for direction in PeekDirection.allCases {
            let tiny = physical.peekWidth(forContentWidth: 10, direction: direction, expandedWidth: 640)
            let huge = physical.peekWidth(forContentWidth: 100_000, direction: direction, expandedWidth: 640)
            let ceiling = direction.isLateral ? physical.maxLateralPeekWidth(expandedWidth: 640) : 640
            check(tiny == physical.collapsedContentWidth,
                  "\(direction.rawValue) peek never shrinks below the collapsed pill")
            check(huge == ceiling, "\(direction.rawValue) peek caps instead of growing unbounded")
            check(tiny < huge, "\(direction.rawValue) peek width tracks its content")
        }
        // A cap below the collapsed pill would shrink it; the floor has to win.
        check(physical.peekWidth(forContentWidth: 100_000, direction: .left, expandedWidth: 1)
                >= physical.collapsedContentWidth,
              "an unusably narrow cap still never shrinks the pill")

        // Longer text must ask for a wider pill, or "size to the content" is a lie.
        let short = PeekMetrics.contentWidth(for: .copied(preview: "Hi"))
        let long = PeekMetrics.contentWidth(for: .copied(preview: String(repeating: "long title ", count: 8)))
        check(long > short, "a longer peek measures wider than a short one")
        check(short > PeekMetrics.horizontalPadding * 2,
              "measurement includes the icon and padding, not just the text")
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
        check(store.peekDirection == .down, "reset restores peekDirection to the classic drop-down")
        check(PeekDirection.allCases.allSatisfy { PeekDirection(rawValue: $0.rawValue) == $0 }, "PeekDirection round-trips")
        check(!store.audioVisualizerEnabled, "reset restores audioVisualizerEnabled to off (needs explicit opt-in)")
    }

    print("AudioVisualizerEngine")
    do {
        check(AudioVisualizerEngine.bandCount >= 16, "enough bands for a detailed circular spectrum")
        let engine = AudioVisualizerEngine.shared
        check(engine.bars.count == AudioVisualizerEngine.bandCount, "starts with one level per band")
        check(!engine.isCapturing, "not capturing until explicitly started")
        // The collapsed pill downsamples the full spectrum; the circular view uses
        // all of it. Both must come from the same single FFT.
        check(engine.compactBars(count: 4).count == 4, "compactBars downsamples to the requested bucket count")
        check(engine.compactBars(count: 1).count == 1, "compactBars handles a single bucket")
        check(engine.compactBars(count: 0).isEmpty, "compactBars handles a zero bucket count without crashing")
    }

    print("ArtworkLoader")
    do {
        // Spotify's AppleScript usually hands back the 300px thumbnail, which is barely
        // enough for the panel's art at 2x. The size is encoded in the image ID, so the
        // 640px version is the same asset under a different prefix.
        func upgrade(_ string: String) -> String? {
            URL(string: string).flatMap(ArtworkLoader.highestResolutionSpotifyURL(from:))?.absoluteString
        }
        let hash = "5f7f1f4a2b3c4d5e6f708192"
        check(upgrade("https://i.scdn.co/image/ab67616d00001e02\(hash)")
                == "https://i.scdn.co/image/ab67616d0000b273\(hash)",
              "the 300px Spotify variant is upgraded to 640px")
        check(upgrade("https://i.scdn.co/image/ab67616d00004851\(hash)")
                == "https://i.scdn.co/image/ab67616d0000b273\(hash)",
              "the 64px Spotify variant is upgraded to 640px")
        // Already-large and unrecognised URLs return nil so the caller keeps the
        // original rather than requesting something that may not exist.
        check(upgrade("https://i.scdn.co/image/ab67616d0000b273\(hash)") == nil,
              "an already-640px URL needs no upgrade")
        check(upgrade("https://example.com/cover.jpg") == nil,
              "an unrecognised artwork URL is left alone")
        check(upgrade("https://i.scdn.co/image/ab67616d0000") == nil,
              "a truncated image ID is left alone rather than mangled")

        // NSImage takes its size from DPI metadata, so a 600px cover tagged at 144dpi
        // reports 300pt and can be drawn softer than the bitmap it holds.
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 600,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        let image = NSImage(size: NSSize(width: 300, height: 300))
        image.addRepresentation(rep)
        check(ArtworkLoader.normalizedToPixelSize(image).size == NSSize(width: 600, height: 600),
              "artwork size is restated in pixels rather than DPI-derived points")
    }

    print("PlaybackProgress")
    do {
        let start = Date()
        let playing = PlaybackProgress(elapsed: 30, duration: 120, sampledAt: start, isPlaying: true)
        // The sample is only refreshed every few seconds, so the bar has to extrapolate
        // between readings or it visibly steps.
        check(playing.fraction(at: start) == 0.25, "fraction at the sample instant is the sampled position")
        check(playing.elapsed(at: start.addingTimeInterval(30)) == 60,
              "elapsed extrapolates forward while playing")
        check(playing.elapsed(at: start.addingTimeInterval(9999)) == 120,
              "extrapolation never runs past the end of the track")
        check(playing.fraction(at: start.addingTimeInterval(9999)) == 1, "fraction stays within 0...1")

        let paused = PlaybackProgress(elapsed: 30, duration: 120, sampledAt: start, isPlaying: false)
        check(paused.elapsed(at: start.addingTimeInterval(60)) == 30,
              "a paused track's position doesn't drift")

        // Streams and some local files report no duration; the bar hides rather than
        // rendering as empty or full.
        let unmeasurable = PlaybackProgress(elapsed: 5, duration: 0, sampledAt: start, isPlaying: true)
        check(!unmeasurable.isMeasurable, "a track with no duration is not measurable")
        check(unmeasurable.fraction(at: start) == 0, "an unmeasurable track reports no progress")
        check(playing.isMeasurable, "a normal track is measurable")

        // Spotify reports duration in milliseconds and Music in seconds, for the same
        // AppleScript property — reading both as one unit is out by 1000x.
        check(MediaApp.spotify.durationIsMilliseconds && !MediaApp.music.durationIsMilliseconds,
              "duration units differ per app")
    }

    print("NowPlaying layout")
    do {
        // Regression guard: album art and the circular visualizer are both squares
        // driven by the panel's *height*, either side of a metadata column whose
        // transport row can't shrink. Sizing art on height alone overflowed at narrow
        // widths — at 420x210 the metadata column was left 12pt, and at 420x340 it
        // went negative. Both reachable from the Settings sliders.
        //
        // Derived from the same constants the views render with, so widening the
        // panel insets or growing the transport buttons fails here rather than
        // silently overflowing on someone's screen.
        let notchHeight: CGFloat = 32 // virtual notch; a real one is similar
        var worstCase: CGFloat = .greatestFiniteMagnitude
        var worstAt = ""
        var visualizerOverflowAt: String?
        for width in stride(from: 420.0, through: 900.0, by: 10.0) {
            for height in stride(from: 140.0, through: 340.0, by: 10.0) {
                let contentWidth = ExpandedNotchView.contentWidth(panelWidth: CGFloat(width))
                let contentHeight = ExpandedNotchView.contentHeight(panelHeight: CGFloat(height) + notchHeight)
                // Visualizer on is the tighter case — it's what shrinks the song
                // column to its share — so the guard only has to sweep that one.
                let song = NowPlayingLayout.songColumnWidth(availableWidth: contentWidth,
                                                            availableHeight: contentHeight,
                                                            hasVisualizer: true)
                let art = NowPlayingLayout.artSize(availableHeight: contentHeight,
                                                   songColumnWidth: song)
                let metadata = NowPlayingLayout.metadataWidth(songColumnWidth: song, artSize: art)
                if metadata < worstCase {
                    worstCase = metadata
                    worstAt = "\(Int(width))x\(Int(height))"
                }

                // The visualizer is a square in a fixed region: it has to fit that
                // region *and* the panel height, or it overflows at wide-and-short
                // settings. Accumulated across the sweep and asserted once, rather
                // than printing a line per combination.
                let visualizer = NowPlayingLayout.visualizerSize(availableWidth: contentWidth,
                                                                 availableHeight: contentHeight)
                let region = NowPlayingLayout.visualizerRegionWidth(availableWidth: contentWidth,
                                                                    availableHeight: contentHeight)
                if visualizer <= 0 || visualizer > contentHeight + 0.001 || visualizer > region + 0.001 {
                    visualizerOverflowAt = "\(Int(width))x\(Int(height))"
                }
            }
        }
        check(visualizerOverflowAt == nil,
              "visualizer fits its region and the panel height at every size"
                + (visualizerOverflowAt.map { " (overflowed at \($0))" } ?? ""))
        check(worstCase >= NowPlayingLayout.transportRowMinimum + NowPlayingLayout.metadataBreathingRoom,
              "metadata column never collapses below the transport row (worst \(Int(worstCase))pt at \(worstAt), need \(Int(NowPlayingLayout.transportRowMinimum))pt)")
        check(NowPlayingLayout.songColumnFraction + (1 - NowPlayingLayout.songColumnFraction) == 1,
              "song column and visualizer region tile the panel exactly")

        // Whatever the progress bar is allowed to draw must actually fit the metadata
        // column's spare height, or it pushes the transport row out of the panel.
        var progressOverflowAt: String?
        for width in stride(from: 420.0, through: 900.0, by: 10.0) {
            for height in stride(from: 140.0, through: 340.0, by: 10.0) {
                let contentWidth = ExpandedNotchView.contentWidth(panelWidth: CGFloat(width))
                let contentHeight = ExpandedNotchView.contentHeight(panelHeight: CGFloat(height) + notchHeight)
                let song = NowPlayingLayout.songColumnWidth(availableWidth: contentWidth,
                                                            availableHeight: contentHeight,
                                                            hasVisualizer: true)
                let art = NowPlayingLayout.artSize(availableHeight: contentHeight, songColumnWidth: song)
                let spare = art - NowPlayingLayout.metadataFixedHeight - NowPlayingLayout.metadataSpacerMinimum
                let needed: CGFloat
                switch NowPlayingLayout.progressStyle(columnHeight: art) {
                case .hidden:     needed = 0
                case .barOnly:    needed = NowPlayingLayout.progressBarOnlyHeight
                case .withLabels: needed = NowPlayingLayout.progressBarWithLabelsHeight
                }
                if needed > max(spare, 0) + 0.001 { progressOverflowAt = "\(Int(width))x\(Int(height))" }
            }
        }
        check(progressOverflowAt == nil,
              "progress bar only shown where the metadata column has room for it"
                + (progressOverflowAt.map { " (overflowed at \($0))" } ?? ""))
        check(NowPlayingLayout.progressStyle(columnHeight: 0) == .hidden,
              "progress bar is dropped entirely when there's no room")
        check(NowPlayingLayout.progressStyle(columnHeight: 1000) == .withLabels,
              "progress bar shows its timestamps when there's plenty of room")
    }

    print(failures == 0 ? "\nAll checks passed ✅" : "\n\(failures) check(s) failed ❌")
    return failures
}
