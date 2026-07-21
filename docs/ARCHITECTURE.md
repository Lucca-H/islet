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
                               ├── CollapsedNotchView   (solid black, exact notch silhouette)
                               ├── PeekContentView       (brief live-activity hint)
                               └── ExpandedNotchView     (GlassEffectView) → {NowPlaying, Shelf, Clipboard} views
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

## Visual surface: three states, one window

`NotchRootView` renders one of three states from a single window, always clipped to
`NotchShape` — a custom `Shape` with concave "shoulder" corners that hug the physical
notch:

- **Collapsed** — the resting state.
- **Peek** — the same shape, briefly widened (`NotchViewModel.showPeek`), showing a
  small icon + one line of text. Auto-dismisses after ~2s; never fires while the notch
  is expanded or hovered.
- **Expanded** — the notch fully opens.

**Material follows `SettingsStore.notchMaterial`.** In **Solid** mode the notch is
opaque black in all three states, no exceptions. In **Liquid Glass** mode, the notch
stays opaque black through collapsed and peek — reading as an extension of the
physical hardware bezel — and only reveals real translucency (AppKit's native
`NSGlassEffectView`, bridged into SwiftUI as `GlassBackground`) once actually
*expanded*. Nothing is glass while collapsed; the glass content is only meaningful (and
only interactive) once open.

Both the black fill and the glass layer are **permanently present views**, never
structurally inserted or removed — only their opacity animates between 0 and 1,
crossed over together (black fades out as glass fades in). That distinction matters:
earlier versions broke this twice.

- **Don't structurally swap between materials.** An `if isExpanded { glassTree } else
  { blackTree }` was the very first version. SwiftUI can't animate across two different
  view identities, so the glass tint popped in instantly instead of transitioning with
  the resize.
- **Don't leave an opaque layer permanently behind the glass.** Fixing the above by
  keeping *both* layers permanently present but leaving the black fill at opacity 1
  the whole time seemed like the fix — until it was clear there was no transparency at
  all. `NSGlassEffectView` refracts whatever is actually drawn behind it; a
  permanently-opaque black layer behind it means it refracts its own black, not the
  desktop, and reads as solid regardless of its own opacity. The black layer's opacity
  has to actually reach 0 for the glass above it to mean anything — which is exactly
  what "black until opened" requires anyway: fade the black *out* as the glass fades
  *in*, both keyed off the same `isExpanded` transition.

Two more rules, both about not fighting a *second* glass view:

- **Don't host SwiftUI inside `NSGlassEffectView.contentView`.** It manages its own
  content layout, and swapping a hosted SwiftUI tree underneath it (changing notch tabs)
  makes the effect drop out. `GlassBackground` renders glass *behind* ordinary SwiftUI
  content instead, which looks identical for an opaque panel.
- **Don't nest glass inside glass.** The selected tab chip originally used its own
  `NSGlassEffectView`; moving that nested view between tabs killed the parent panel's
  effect. It's now a plain translucent capsule.

`NSGlassEffectView` also only exposes a single uniform `cornerRadius` — it can't mask
to `NotchShape`'s asymmetric silhouette on its own, so `GlassBackground` is clipped to
`NotchShape` from the SwiftUI side rather than relying on the native view's own corner
handling.

## Features

- **NowPlayingManager** is layered, because the obvious approach doesn't work:

  1. **`MediaRemoteBridge` (attempted first, usually unavailable).** A `dlopen`/`dlsym`
     wrapper around the private `MediaRemote.framework`. It *would* give system-wide
     playback including browser/web audio — but on macOS 26 it only returns data to
     Apple-signed binaries. Verified directly: identical code returns 30 populated keys
     when run inside Apple's `swift-frontend`, and an empty dictionary from an
     ad-hoc-signed `.app` bundle, at the same instant with the same track playing.
     Neither entitlements nor bundling changes this. The bridge self-disables after
     three empty replies so it costs nothing, and would light up automatically if a
     build ever gains access.
  2. **Distributed notifications (the real backbone).** Music and Spotify each post a
     `DistributedNotificationCenter` notification on every playback change, carrying
     `Name` / `Artist` / `Album` / `Player State` in `userInfo`. This needs no
     entitlement and triggers no permission prompt, and it's push-based, so updates
     are instant.
  3. **AppleScript (gap-filler).** Notifications only fire on *change*, so AppleScript
     reads state at launch, fetches artwork, and sends transport commands. These need
     Automation permission; if the user declines, metadata still flows from step 2.

  Because an AppleScript poll returns empty when Automation is denied, an empty poll
  never clears state the notification feed recently supplied (`notificationTrustWindow`).

  Two sharp edges worth knowing: AppleScript rejects short variable names like `st`
  (parsed as the ordinal "1st"), and a `tell application "X"` block fails to *compile*
  when X isn't installed — so scripts are only ever run for apps confirmed running.
- **DropShelfManager** copies dropped files into `~/Library/Application Support/Islet/Shelf`
  and vends them back as draggable `NSItemProvider`s.
- **ClipboardManager** polls `NSPasteboard.changeCount`, records text/images, de-duplicates,
  trims to the configured limit, and skips `org.nspasteboard.ConcealedType`/`TransientType`.

Both `DropShelfManager` and `ClipboardManager` publish Combine events (`itemAdded`,
`itemCaptured`) that `AppDelegate` forwards into `NotchViewModel.showPeek`, alongside
`NowPlayingManager.playbackStarted` — one mechanism drives all three live activities.

## Settings

`SettingsStore` is a shared `ObservableObject`; each property mirrors a `UserDefaults` key and
persists on change. Views observe it, and both `AppDelegate` (feature lifecycle, screen
targeting) and `NotchController` (size/shape) react live — no relaunch needed.

## Testing

Command Line Tools ship neither XCTest nor swift-testing, so the same assertions exist twice:
`Sources/IsletCore/SelfChecks.swift` (runs anywhere via `swift run IsletChecks`) and
`Tests/IsletTests/` (swift-testing, run by `swift test` in CI where Xcode is present). Keep the
two in sync when adding logic.
