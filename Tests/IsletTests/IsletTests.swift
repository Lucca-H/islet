import Testing
import SwiftUI
import AppKit
@testable import IsletCore

// MARK: NotchShape

@Test func notchShapeProducesNonEmptyClosedPath() {
    let shape = NotchShape(bottomRadius: 20, topRadius: 10)
    let rect = CGRect(x: 0, y: 0, width: 400, height: 120)
    let path = shape.path(in: rect)
    #expect(!path.isEmpty)
    #expect(rect.insetBy(dx: -1, dy: -1).contains(path.boundingRect))
}

@Test func notchShapeClampsRadiiToRect() {
    let shape = NotchShape(bottomRadius: 9999, topRadius: 9999)
    let rect = CGRect(x: 0, y: 0, width: 50, height: 40)
    let path = shape.path(in: rect)
    #expect(!path.isEmpty)
    #expect(rect.insetBy(dx: -1, dy: -1).contains(path.boundingRect))
}

// MARK: Enums round-trip

@Test func expandTriggerRawRoundTrip() {
    for trigger in ExpandTrigger.allCases {
        #expect(ExpandTrigger(rawValue: trigger.rawValue) == trigger)
    }
}

@Test func screenTargetingRawRoundTrip() {
    for targeting in ScreenTargeting.allCases {
        #expect(ScreenTargeting(rawValue: targeting.rawValue) == targeting)
    }
}

private func makeInfo(_ title: String) -> NowPlayingInfo {
    NowPlayingInfo(title: title, artist: "Artist", album: "Album", isPlaying: true,
                   sourceName: "Music", sourceBundleID: "com.apple.Music")
}

@Test func nowPlayingInfoEquality() {
    #expect(makeInfo("Song") == makeInfo("Song"))
    #expect(makeInfo("Song") != makeInfo("Other"))
    #expect(makeInfo("Song").trackKey != makeInfo("Other").trackKey)
}

@Test func mediaAppIdentifiers() {
    #expect(MediaApp.music.bundleID == "com.apple.Music")
    #expect(MediaApp.spotify.bundleID == "com.spotify.client")
    #expect(MediaApp.music.notificationName.rawValue == "com.apple.iTunes.playerInfo")
    #expect(MediaApp.spotify.notificationName.rawValue == "com.spotify.client.PlaybackStateChanged")
}

/// Regression guard: AppleScript parses short names like `st` as the ordinal "1st"
/// and raises a syntax error, which silently broke all metadata queries.
@Test func metadataScriptAvoidsReservedShortNames() {
    for app in MediaApp.allCases {
        let script = app.metadataScript(separator: "|")
        #expect(script.contains("is running"))   // must never launch the app
        #expect(!script.contains("set st to"))
        #expect(script.contains("theState"))
    }
}

@Test func notchPeekFormatting() {
    let peek = NotchPeek.fileAdded(name: "report.pdf")
    #expect(peek.text == "Added report.pdf")
    #expect(!peek.symbol.isEmpty)
}

// MARK: ClipItem equality

@Test func clipItemTextEquality() {
    #expect(ClipItem.Kind.text("hello") == ClipItem.Kind.text("hello"))
    #expect(ClipItem.Kind.text("hello") != ClipItem.Kind.text("world"))
}

@Test func clipItemTextImageMismatch() {
    let image = NSImage(size: NSSize(width: 2, height: 2))
    #expect(ClipItem.Kind.text("x") != ClipItem.Kind.image(image))
}

// MARK: NotchTab

@Test func everyTabHasSymbolAndTitle() {
    for tab in NotchTab.allCases {
        #expect(!tab.title.isEmpty)
        #expect(!tab.symbol.isEmpty)
    }
}

// MARK: SettingsStore defaults

@MainActor
@Test func settingsResetRestoresDefaults() {
    let store = SettingsStore.shared
    store.expandedWidth = 800
    store.clipboardLimit = 5
    store.nowPlayingEnabled = false
    store.notchMaterial = .solid
    store.audioVisualizerEnabled = true
    store.quickNoteEnabled = false
    store.resetToDefaults()
    #expect(store.expandedWidth == 640)
    #expect(store.clipboardLimit == 50)
    #expect(store.nowPlayingEnabled == true)
    #expect(store.notchMaterial == .liquidGlass)
    #expect(store.audioVisualizerEnabled == false)
    #expect(store.quickNoteEnabled == true)
}

@Test func notchMaterialRawRoundTrip() {
    for material in NotchMaterial.allCases {
        #expect(NotchMaterial(rawValue: material.rawValue) == material)
    }
}

@MainActor
@Test func audioVisualizerEngineDefaults() {
    #expect(AudioVisualizerEngine.bandCount >= 16)
    let engine = AudioVisualizerEngine.shared
    #expect(engine.bars.count == AudioVisualizerEngine.bandCount)
    #expect(engine.isCapturing == false)
}

/// The collapsed pill downsamples the full spectrum while the circular visualizer
/// uses all of it — both driven by the same single FFT.
@MainActor
@Test func compactBarsDownsamplesToRequestedCount() {
    let engine = AudioVisualizerEngine.shared
    #expect(engine.compactBars(count: 4).count == 4)
    #expect(engine.compactBars(count: 1).count == 1)
    #expect(engine.compactBars(count: 0).isEmpty)
}

// MARK: NotchGeometry content-safe margin

/// Regression guard: the physical notch cutout has zero real, displayable pixels.
/// Content drawn exactly within its width is invisible, not merely cramped — the
/// collapsed pill must always be wider than the bare cutout on real hardware.
@Test func collapsedPillIsWiderThanTheBareNotchOnRealHardware() {
    let physical = NotchGeometry(screen: NSScreen.main ?? NSScreen.screens[0],
                                 notchRect: CGRect(x: 0, y: 0, width: 200, height: 32),
                                 hasPhysicalNotch: true)
    #expect(physical.collapsedContentWidth > physical.notchWidth)
    #expect(physical.contentSafeMargin > 0)
}

/// Regression guard: the expanded panel is far wider than the notch and centered on
/// it, so its top-center region lands behind the camera housing. Content has to start
/// below the band, or the tab strip is invisible on real hardware.
@Test func expandedContentIsInsetBelowTheNotchBand() {
    let physical = NotchGeometry(screen: NSScreen.main ?? NSScreen.screens[0],
                                 notchRect: CGRect(x: 0, y: 0, width: 200, height: 32),
                                 hasPhysicalNotch: true)
    #expect(physical.contentTopInset == physical.notchHeight)
}

@Test func noExtraMarginOnNotchlessDisplays() {
    let virtual = NotchGeometry(screen: NSScreen.main ?? NSScreen.screens[0],
                                notchRect: CGRect(x: 0, y: 0, width: 220, height: 32),
                                hasPhysicalNotch: false)
    #expect(virtual.collapsedContentWidth == virtual.notchWidth)
    #expect(virtual.contentTopInset == 0)
}

// MARK: Sideways peek geometry

/// A sideways peek pins the edge it grows away from to the collapsed pill's, so all
/// the extra width lands on the growth side — and a peek with no extra width to add
/// doesn't move at all, which would otherwise slide the pill off the notch.
@Test func sidewaysPeekShiftsByHalfItsExtraWidth() {
    let physical = NotchGeometry(screen: NSScreen.main ?? NSScreen.screens[0],
                                 notchRect: CGRect(x: 0, y: 0, width: 200, height: 32),
                                 hasPhysicalNotch: true)
    #expect(physical.lateralPeekShift(peekWidth: physical.collapsedContentWidth + 200) == 100)
    #expect(physical.lateralPeekShift(peekWidth: physical.collapsedContentWidth) == 0)
    #expect(physical.lateralPeekShift(peekWidth: 10) == 0)
}

@Test func peekDirectionsShiftOppositeWays() {
    #expect(PeekDirection.left.lateralSign == -1)
    #expect(PeekDirection.right.lateralSign == 1)
    #expect(PeekDirection.down.lateralSign == 0)
    #expect(!PeekDirection.down.isLateral)
    #expect(PeekDirection.left.isLateral && PeekDirection.right.isLateral)
}

/// The peek opens as far as its text needs and no further — but a pathological title
/// must not be able to drag the pill past what the window can actually draw, and a
/// short one must not shrink it below its resting size.
@Test func peekWidthTracksContentWithinBounds() {
    let physical = NotchGeometry(screen: NSScreen.main ?? NSScreen.screens[0],
                                 notchRect: CGRect(x: 0, y: 0, width: 200, height: 32),
                                 hasPhysicalNotch: true)
    for direction in PeekDirection.allCases {
        let tiny = physical.peekWidth(forContentWidth: 10, direction: direction, expandedWidth: 640)
        let huge = physical.peekWidth(forContentWidth: 100_000, direction: direction, expandedWidth: 640)
        let ceiling = direction.isLateral ? physical.maxLateralPeekWidth(expandedWidth: 640) : 640
        #expect(tiny == physical.collapsedContentWidth)
        #expect(huge == ceiling)
        #expect(tiny < huge)
    }
}

/// A cap below the collapsed pill would shrink it — the floor has to win over the cap.
@Test func peekNeverShrinksBelowTheCollapsedPill() {
    let physical = NotchGeometry(screen: NSScreen.main ?? NSScreen.screens[0],
                                 notchRect: CGRect(x: 0, y: 0, width: 200, height: 32),
                                 hasPhysicalNotch: true)
    #expect(physical.peekWidth(forContentWidth: 100_000, direction: .left, expandedWidth: 1)
              >= physical.collapsedContentWidth)
}

/// Longer text has to measure wider, or sizing the pill to its content is a lie.
@Test func peekMeasurementTracksTextLength() {
    let short = PeekMetrics.contentWidth(for: .copied(preview: "Hi"))
    let long = PeekMetrics.contentWidth(for: .copied(preview: String(repeating: "long title ", count: 8)))
    #expect(long > short)
    #expect(short > PeekMetrics.horizontalPadding * 2)
}

/// The notch window is only `expandedWidth` wide (plus shadow slack) and centered on
/// the notch, so a sideways pill has to stop before the window edge — past it the
/// pill clips against a plain rectangle instead of `NotchShape`.
@Test func sidewaysPeekStaysInsideTheNotchWindow() {
    let physical = NotchGeometry(screen: NSScreen.main ?? NSScreen.screens[0],
                                 notchRect: CGRect(x: 0, y: 0, width: 200, height: 32),
                                 hasPhysicalNotch: true)
    let limit = physical.maxLateralPeekWidth(expandedWidth: 640)
    #expect(physical.lateralPeekShift(peekWidth: limit) + limit / 2 <= 320)
    #expect(physical.peekLateralDeadWidth > physical.notchWidth)
}

// MARK: QuickNoteManager

@MainActor
@Test func quickNoteManagerPersistsAndClears() {
    let defaults = UserDefaults(suiteName: "com.dynamicisland.islet.tests.quicknote")!
    defaults.removePersistentDomain(forName: "com.dynamicisland.islet.tests.quicknote")
    let manager = QuickNoteManager(defaults: defaults)
    #expect(manager.text.isEmpty)
    #expect(manager.lastEditedAt == nil)
    manager.text = "buy milk"
    #expect(manager.lastEditedAt != nil)
    manager.clear()
    #expect(manager.text.isEmpty)
}

@Test func quickNoteIsARealTab() {
    #expect(NotchTab.allCases.contains(.quickNote))
}

// MARK: NowPlaying layout

/// Regression guard: the album art is a square driven by the panel's *height*, beside
/// a metadata column whose transport row can't shrink below ~130pt — and the song
/// column holding both is now capped at its share of the panel rather than taking
/// whatever it likes. Sizing art on height alone overflowed at narrow widths: at
/// 420x210 the metadata column was left 12pt, at 420x340 it went negative, and both
/// are reachable from the Settings sliders.
@MainActor
@Test func metadataColumnSurvivesEverySizeSetting() {
    let notchHeight: CGFloat = 32
    for width in stride(from: 420.0, through: 900.0, by: 10.0) {
        for height in stride(from: 140.0, through: 340.0, by: 10.0) {
            let contentWidth = ExpandedNotchView.contentWidth(panelWidth: CGFloat(width))
            let contentHeight = ExpandedNotchView.contentHeight(panelHeight: CGFloat(height) + notchHeight)
            // Visualizer on is the tighter case — it's what caps the song column.
            let song = NowPlayingLayout.songColumnWidth(availableWidth: contentWidth,
                                                        availableHeight: contentHeight,
                                                        hasVisualizer: true)
            let art = NowPlayingLayout.artSize(availableHeight: contentHeight,
                                               songColumnWidth: song)
            let metadata = NowPlayingLayout.metadataWidth(songColumnWidth: song, artSize: art)
            #expect(metadata >= NowPlayingLayout.transportRowMinimum + NowPlayingLayout.metadataBreathingRoom,
                    "metadata column collapsed at \(width)x\(height): \(metadata)pt")
        }
    }
}

// MARK: ArtworkLoader

/// Spotify's `artwork url of current track` usually hands back the 300px thumbnail,
/// which is barely enough for the panel's art on a 2x display. The dimension is encoded
/// in the image ID, so the 640px version is the same asset under a different prefix.
@Test func spotifyArtworkUpgradesToTheLargestVariant() {
    let hash = "5f7f1f4a2b3c4d5e6f708192"
    func upgrade(_ string: String) -> String? {
        URL(string: string).flatMap(ArtworkLoader.highestResolutionSpotifyURL(from:))?.absoluteString
    }
    #expect(upgrade("https://i.scdn.co/image/ab67616d00001e02\(hash)")
              == "https://i.scdn.co/image/ab67616d0000b273\(hash)")
    #expect(upgrade("https://i.scdn.co/image/ab67616d00004851\(hash)")
              == "https://i.scdn.co/image/ab67616d0000b273\(hash)")
}

/// Already-large and unrecognised URLs return nil, so the caller keeps the original
/// rather than requesting a rewrite that may not exist.
@Test func unrecognisedArtworkURLsAreLeftAlone() {
    let hash = "5f7f1f4a2b3c4d5e6f708192"
    func upgrade(_ string: String) -> URL? {
        URL(string: string).flatMap(ArtworkLoader.highestResolutionSpotifyURL(from:))
    }
    #expect(upgrade("https://i.scdn.co/image/ab67616d0000b273\(hash)") == nil)
    #expect(upgrade("https://example.com/cover.jpg") == nil)
    #expect(upgrade("https://i.scdn.co/image/ab67616d0000") == nil)
}

/// `NSImage` takes its size from DPI metadata, so a 600px cover tagged at 144dpi
/// reports 300pt and can be drawn softer than the bitmap it actually holds.
@Test func artworkSizeIsRestatedInPixels() {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 600,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let image = NSImage(size: NSSize(width: 300, height: 300))
    image.addRepresentation(rep)
    #expect(ArtworkLoader.normalizedToPixelSize(image).size == NSSize(width: 600, height: 600))
}

// MARK: PlaybackProgress

/// Position comes from a 3-second AppleScript poll, so the bar has to extrapolate
/// between samples or it visibly steps — but never past the end of the track, and
/// never at all while paused.
@Test func playbackProgressExtrapolatesBetweenSamples() {
    let start = Date()
    let playing = PlaybackProgress(elapsed: 30, duration: 120, sampledAt: start, isPlaying: true)
    #expect(playing.fraction(at: start) == 0.25)
    #expect(playing.elapsed(at: start.addingTimeInterval(30)) == 60)
    #expect(playing.elapsed(at: start.addingTimeInterval(9999)) == 120)
    #expect(playing.fraction(at: start.addingTimeInterval(9999)) == 1)

    let paused = PlaybackProgress(elapsed: 30, duration: 120, sampledAt: start, isPlaying: false)
    #expect(paused.elapsed(at: start.addingTimeInterval(60)) == 30)
}

/// Streams and some local files report no duration — the bar hides rather than
/// rendering as permanently empty or full.
@Test func playbackProgressHandlesUnknownDuration() {
    let unmeasurable = PlaybackProgress(elapsed: 5, duration: 0, sampledAt: Date(), isPlaying: true)
    #expect(!unmeasurable.isMeasurable)
    #expect(unmeasurable.fraction(at: Date()) == 0)
}

/// Spotify reports `duration of current track` in milliseconds and Music in seconds,
/// for the same property name — reading both as one unit is out by a factor of 1000.
@Test func durationUnitsDifferPerApp() {
    #expect(MediaApp.spotify.durationIsMilliseconds)
    #expect(!MediaApp.music.durationIsMilliseconds)
}

/// Whatever the progress bar draws has to fit the metadata column's spare height, or
/// it pushes the transport row out of the panel.
@MainActor
@Test func progressBarOnlyShownWhereItFits() {
    let notchHeight: CGFloat = 32
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
            #expect(needed <= max(spare, 0) + 0.001, "progress bar overflowed at \(width)x\(height)")
        }
    }
    #expect(NowPlayingLayout.progressStyle(columnHeight: 0) == .hidden)
    #expect(NowPlayingLayout.progressStyle(columnHeight: 1000) == .withLabels)
}

/// The visualizer is a square inside a fixed-width region, so it has to fit both that
/// region and the panel's height — width alone overflows it at wide-and-short sizes.
@MainActor
@Test func visualizerFitsItsRegionAtEverySizeSetting() {
    let notchHeight: CGFloat = 32
    for width in stride(from: 420.0, through: 900.0, by: 10.0) {
        for height in stride(from: 140.0, through: 340.0, by: 10.0) {
            let contentWidth = ExpandedNotchView.contentWidth(panelWidth: CGFloat(width))
            let contentHeight = ExpandedNotchView.contentHeight(panelHeight: CGFloat(height) + notchHeight)
            let size = NowPlayingLayout.visualizerSize(availableWidth: contentWidth,
                                                       availableHeight: contentHeight)
            let region = NowPlayingLayout.visualizerRegionWidth(availableWidth: contentWidth,
                                                                availableHeight: contentHeight)
            #expect(size > 0, "visualizer vanished at \(width)x\(height)")
            #expect(size <= contentHeight + 0.001, "visualizer overflowed height at \(width)x\(height)")
            #expect(size <= region + 0.001, "visualizer overflowed its region at \(width)x\(height)")
        }
    }
}
