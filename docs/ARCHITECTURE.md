# Architecture

A quick tour of how Islet is put together.

## Big picture

Islet is a menu-bar (`LSUIElement`) app. It draws a floating, always-on-top panel over the
notch on each target screen and expands it on hover. Everything below the app entry point
lives in the `IsletCore` library so it can be imported by the executable, the self-check
runner, and the tests.

```
main.swift ──▶ AppDelegate
                 │
                 ├── SettingsStore (shared, persisted to UserDefaults)
                 ├── NowPlayingManager ─┐
                 ├── DropShelfManager   ├─ shared feature managers
                 ├── ClipboardManager  ─┘
                 ├── StatusBarController (menu-bar item)
                 └── one NotchController per target screen
                        ├── NotchWindow (borderless NSPanel)
                        ├── NotchViewModel (expansion state + selected tab)
                        └── NotchRootView (SwiftUI)
                               ├── CollapsedNotchView
                               └── ExpandedNotchView → {NowPlaying, Shelf, Clipboard} views
```

## Notch window & hover

`NotchWindow` is a borderless, non-activating `NSPanel` at a very high window level with
`canJoinAllSpaces + fullScreenAuxiliary`, so it floats above the menu bar and full-screen apps.

The window always covers the full *expanded* footprint. While collapsed it is click-through
(`ignoresMouseEvents = true`) so only the notch reacts; `NotchController` flips that off once
expanded so buttons and drops work.

Hover is driven by a **global + local `NSEvent` mouse monitor** in `AppDelegate`. Each
`NotchController` compares the pointer against a *collapsed region* (opens the notch) and an
*expanded region* (leaving it closes the notch). This avoids relying on SwiftUI hit-testing
through transparent window areas.

`ScreenNotch` resolves the notch rectangle from `NSScreen.auxiliaryTopLeftArea/RightArea`, and
synthesizes a centered virtual handle on notchless displays.

## Features

- **NowPlayingManager** polls Music/Spotify with `osascript` every 1.5 s. It intentionally
  avoids the private MediaRemote framework, which Apple restricted behind a private entitlement
  in recent macOS, so a third-party app can no longer read the system Now Playing feed reliably.
- **DropShelfManager** copies dropped files into `~/Library/Application Support/Islet/Shelf`
  and vends them back as draggable `NSItemProvider`s.
- **ClipboardManager** polls `NSPasteboard.changeCount`, records text/images, de-duplicates,
  trims to the configured limit, and skips `org.nspasteboard.ConcealedType`/`TransientType`.

## Settings

`SettingsStore` is a shared `ObservableObject`; each property mirrors a `UserDefaults` key and
persists on change. Views observe it, and both `AppDelegate` (feature lifecycle, screen
targeting) and `NotchController` (size/shape) react live — no relaunch needed.

## Testing

Command Line Tools ship neither XCTest nor swift-testing, so the same assertions exist twice:
`Sources/IsletCore/SelfChecks.swift` (runs anywhere via `swift run IsletChecks`) and
`Tests/IsletTests/` (swift-testing, run by `swift test` in CI where Xcode is present). Keep the
two in sync when adding logic.
