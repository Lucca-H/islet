import Testing
import SwiftUI
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

@Test func nowPlayingInfoEquality() {
    let a = NowPlayingInfo(title: "Song", artist: "Artist", album: "Album", isPlaying: true, sourceName: "Chrome")
    let b = NowPlayingInfo(title: "Song", artist: "Artist", album: "Album", isPlaying: true, sourceName: "Chrome")
    let c = NowPlayingInfo(title: "Other", artist: "Artist", album: "Album", isPlaying: true, sourceName: "Chrome")
    #expect(a == b)
    #expect(a != c)
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
    store.resetToDefaults()
    #expect(store.expandedWidth == 640)
    #expect(store.clipboardLimit == 50)
    #expect(store.nowPlayingEnabled == true)
}
