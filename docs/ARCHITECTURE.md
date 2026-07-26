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

**The notch cutout itself has zero real, displayable pixels.** Content drawn exactly
within `NotchGeometry.notchWidth` — the true camera-housing gap — is not merely
cramped, it is physically unable to be seen. `NotchGeometry.contentSafeMargin` (36pt
each side on real hardware, 0 on the synthesized virtual notch) extends the collapsed
pill's rendered width and its hover hit-region equally into the real pixels flanking
the cutout, which is where collapsed-state content (album art, audio bars) actually
has to live. `NotchRootView.collapsedSize` and `NotchController.collapsedRegion` both
derive from the same `NotchGeometry` value, so what's drawn and what's hoverable never
drift apart.

**`ClickShieldWindow`** is a second, transparent, screen-spanning `NSPanel` that sits
one window level below the notch while it's expanded, existing only to consume the
click that dismisses it — the way clicking to close a menu also swallows the click,
rather than passing it through to whatever's behind. A global `NSEvent` monitor can
observe other apps' clicks but can't consume them; a window of Islet's own can.

Because it covers every screen, when it goes up matters as much as what it does:

- **Only in `.click` trigger mode.** In hover mode the notch dismisses itself when the
  pointer leaves — but not instantly, since `hoverCloseDelay` keeps it expanded a
  moment longer, and the shield spanned everything for that whole window. Moving off
  the notch and clicking straight away (normal, and easily faster than 350ms) got the
  click eaten for a dismissal that had already happened. There is no dismissing click
  to consume in hover mode, so the shield doesn't go up there at all.
- **It stays up until mouse-*up*.** A click is two events; ordering the window out
  during the mouse-down left the up to land on whatever was behind it, so the click was
  split rather than swallowed — enough to trigger anything acting on mouse-up. `hide()`
  is deferred while a click is in flight, with a timeout in case the up never arrives
  (better a leaked click than a screen-wide shield stuck up forever).
- **`acceptsFirstMouse`** is true: Islet is a background app and essentially never
  frontmost, so every click the shield sees is the kind AppKit would otherwise spend on
  activating the app rather than delivering to the view.

## Visual surface: three states, one window

`NotchRootView` renders one of three states from a single window, always clipped to
`NotchShape` — a custom `Shape` with concave "shoulder" corners that hug the physical
notch:

- **Collapsed** — the resting state.
- **Peek** — the same shape, briefly widened (`NotchViewModel.showPeek`), showing a
  small icon + one line of text. Auto-dismisses after ~2s; never fires while the notch
  is expanded or hovered.

  Which way it grows is `SettingsStore.peekDirection`. **Down** (the default) keeps the
  pill centered on the notch and grows it *past* the notch band, so the text row clears
  the camera housing — the same dodge the expanded panel makes with `contentTopInset`.
  **Left** and **Right** instead pin the pill's opposite edge and extend it sideways into
  the menu-bar strip beside the notch. That strip is real, displayable pixels, so a
  sideways peek needs no vertical growth at all and stays exactly as tall as the collapsed
  pill; what it needs instead is an inset at the *pinned* end
  (`NotchGeometry.peekLateralDeadWidth`) keeping its content off the cutout. The shift is
  a plain `.offset` — `NotchGeometry.lateralPeekShift` times `PeekDirection.lateralSign` —
  and it is clamped by `maxLateralPeekWidth`, because `NotchWindow` is only
  `expandedWidth` wide and centered on the notch: a pill that grew past the window edge
  would clip against a rectangle instead of `NotchShape`.

  How *far* it opens comes from `NotchGeometry.peekWidth(forContentWidth:…)`, measuring
  the row rather than adding a fixed amount of growth — otherwise a two-word clipboard
  preview opens the same gap as a long song title, which reads as overshooting. The
  measurement lives in `PeekMetrics`, which the drawing view uses for its own font and
  padding too: measuring with different metrics than are drawn surfaces as either a
  clipped word or a stray gap, so there is deliberately only one copy of them.
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

- **NowPlayingManager** covers **Apple Music and Spotify only**, via two mechanisms:

  1. **Distributed notifications (the backbone).** Both apps post a
     `DistributedNotificationCenter` notification on every playback change, carrying
     `Name` / `Artist` / `Album` / `Player State` in `userInfo`. This needs no
     entitlement and triggers no permission prompt, and it's push-based, so updates
     are instant.
  2. **AppleScript (gap-filler).** Notifications only fire on *change*, so AppleScript
     reads state at launch, fetches artwork, and sends transport commands.

  **Browser/web audio is deliberately out of scope.** The only system-wide API for it
  is the private `MediaRemote.framework`, which on macOS 26 returns data solely to
  Apple-signed callers — verified directly: identical code returned 30 populated keys
  inside Apple's `swift-frontend` and an empty dictionary from an ad-hoc-signed `.app`
  bundle, at the same instant with the same track playing, with neither entitlements
  nor proper bundling changing it. A `MediaRemoteBridge` that tried it first and
  self-disabled after three empty replies used to live here; it was deleted rather
  than kept as a dependency on a private API that could never actually fire, and its
  presence made the layering look more capable than it was.

  Because an AppleScript poll returns empty when Automation is denied, an empty poll
  never clears state the notification feed recently supplied (`notificationTrustWindow`).

  Two sharp edges worth knowing: AppleScript rejects short variable names like `st`
  (parsed as the ordinal "1st"), and a `tell application "X"` block fails to *compile*
  when X isn't installed — so scripts are only ever run for apps confirmed running.
- **DropShelfManager** copies dropped files into `~/Library/Application Support/Islet/Shelf`
  and vends them back as draggable `NSItemProvider`s.
- **ClipboardManager** polls `NSPasteboard.changeCount`, records text/images, de-duplicates,
  trims to the configured limit, and skips `org.nspasteboard.ConcealedType`/`TransientType`.
- **QuickNoteManager** is a single persistent string (not a note-management UI) —
  matching macOS's own Quick Note idea. Debounced writes to `UserDefaults`; `NotchTab.
  quickNote`'s binding into it is hand-built (`Binding(get:set:)`) rather than via
  `$vm.quickNote.text`, since SwiftUI can't form a projected-value binding through a
  reference-typed property held on another object.
- **AudioVisualizerEngine** is opt-in (`SettingsStore.audioVisualizerEnabled`, default
  `false`) and a genuine `static let shared` singleton — Settings needs to show live
  status (authorized? capturing?) from the *exact* running instance, not a lookalike.
  It captures system audio via `ScreenCaptureKit` (`SCStreamConfiguration.
  capturesAudio`, with a throwaway 2×2 video track riding along since `SCStream` has
  no audio-only mode) rather than tapping any specific app, so it works regardless of
  what's actually producing sound. Verified live: this needs **Screen & System Audio
  Recording** permission — the same category Zoom/OBS use, and materially heavier than
  anything else Islet asks for — which is exactly why it's gated behind its own
  Settings toggle instead of ever being assumed on. Raw `Float` samples are mixed to
  mono, windowed (Hann), FFT'd via `vDSP_fft_zrip`, normalized by **automatic gain
  control**, and reduced to 4 log-spaced
  frequency bands (`AudioVisualizerEngine.bandCount`) with an attack/decay envelope
  (fast rise, slower fall) for a lively rather than jittery look. `AudioBars` falls
  back to a non-audio-reactive animation — same bar count — whenever the engine isn't
  actually capturing, so the layout never shifts based on whether the feature is on.

  The AGC step matters more than it sounds. Dividing the FFT magnitudes by a fixed
  constant — what this did originally — makes the visualizer an *output-volume meter*:
  turning Spotify's own volume slider down shrinks the bars even though nothing about
  the music changed, and a quietly-mastered track never lights up. `AudioOutput.
  normalize` instead scales each frame against a rolling `gainReference` that chases the
  loudest band quickly (`referenceAttack`) and falls back slowly (`referenceRelease`),
  so what's displayed is the spectrum's *shape*, not its amplitude. It's reset in
  `stop()` so a session ending mid-loud-passage doesn't open the next one with a stale
  high reference.

  Note there is deliberately **no floor** on the reference. An earlier version had one,
  reasoning that automatic gain would otherwise amplify near-silence to full scale — but
  a floor is also exactly where volume-independence stops, since below it the reference
  can't adapt and levels track amplitude again. That regime was reachable at ordinary
  reduced volume. It went unnoticed in the circular visualizer, whose `peakGain` clamp
  saturates the top bars and masks it, while the mini bars map level linearly and showed
  it plainly — which is worth remembering as a debugging signal: *the two views disagree*
  usually means something upstream is amplitude-dependent and one of them is clipping.
  Silence is instead handled by `silenceThreshold`, zeroing the output outright, which is
  what the floor was really trying to achieve.

Three managers publish Combine events (`DropShelfManager.itemAdded`, `ClipboardManager.
itemCaptured`, `NowPlayingManager.playbackStarted`) that `AppDelegate` forwards into
`NotchViewModel.showPeek` — one mechanism drives all three live activities.

## Settings

`SettingsStore` is a shared `ObservableObject`; each property mirrors a `UserDefaults` key and
persists on change. Views observe it, and both `AppDelegate` (feature lifecycle, screen
targeting) and `NotchController` (size/shape) react live — no relaunch needed.

## Testing

Command Line Tools ship neither XCTest nor swift-testing, so the same assertions exist twice:
`Sources/IsletCore/SelfChecks.swift` (runs anywhere via `swift run IsletChecks`) and
`Tests/IsletTests/` (swift-testing, run by `swift test` in CI where Xcode is present). Keep the
two in sync when adding logic.
