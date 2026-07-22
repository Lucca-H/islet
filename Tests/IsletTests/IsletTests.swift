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
