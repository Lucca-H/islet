# Changelog

All notable changes to Islet are documented here. This project follows
[Semantic Versioning](https://semver.org) and [Keep a Changelog](https://keepachangelog.com).

## [0.1.0-beta.3] — 2026-07-21

### Fixed
- **The audio visualizer never recovered from being denied at launch.**
  `AudioVisualizerEngine.start()` silently no-ops if permission isn't granted at the
  moment it's called — and nothing ever called it again. If the toggle was already on
  from a previous session, the one attempt at launch fails before the user has had a
  chance to grant anything, and the visualizer then sits dark for the rest of the run,
  even after permission is granted in System Settings — the normal flow being launch,
  notice it's dark, go grant it. `AppDelegate` now retries every 2s until it actually
  succeeds. `AudioVisualizerEngine.isAuthorized` also moved from a computed property
  (silently stale — nothing forced a re-render when the OS-level grant changed) to a
  `@Published` one refreshed on every attempt, so the Settings status row now visibly
  updates once permission lands instead of needing a coincidental, unrelated re-render.
- **The expanded panel's tab strip rendered inside the notch band**, putting it behind
  the camera housing on real hardware. The panel is sized `notchHeight + expandedHeight`
  and its doc comment claimed the tab strip was "pinned under the notch" — but no top
  inset was ever applied, so content started at y=0, i.e. inside the band. Because the
  expanded panel is far wider than the notch and centered on it, its top-center region
  lands squarely behind the housing; the collapsed pill's horizontal-margin trick can't
  help a surface that wide. `NotchGeometry.contentTopInset` now pushes expanded *and*
  peek content below the band entirely (0 on notchless displays, which have nothing to
  dodge).
- **The audio visualizer never ran for browser audio — the one case it was uniquely able
  to handle.** It was gated on `nowPlaying.info?.isPlaying`, which only ever becomes true
  for Music/Spotify, so anything playing in a browser kept it switched off even with
  permission granted. ScreenCaptureKit captures *all* system audio, so the capable
  feature was being disabled by the one that structurally can't see browsers. The
  visualizer now runs whenever it's enabled and authorized, and the collapsed notch shows
  its bars on real audio signal (`AudioVisualizerEngine.hasSignal`) even when no track
  metadata exists — which is the only sign of life Islet can offer for web audio.
- **Quick Note's placeholder didn't line up with the text cursor.** `TextEditor` applies
  its own `textContainerInset` and `lineFragmentPadding` whose values aren't publicly
  specified, so the overlaid placeholder was positioned with hand-guessed padding that
  couldn't match. Replaced with `PlainTextView` (an `NSTextView` with both insets zeroed),
  letting placeholder and text share one origin by construction. The placeholder now also
  disappears as soon as the field is focused, rather than only once text exists.
- **Collapsed-state content was invisible, hidden behind the physical camera housing.**
  The collapsed pill was sized to exactly match the notch's true pixel cutout
  (`NotchGeometry.notchWidth`) — but that cutout has zero real, displayable pixels, so
  anything drawn inside it (album art, audio bars) was physically unable to be seen. The
  collapsed pill now extends a safe margin (`NotchGeometry.contentSafeMargin`, 36pt each
  side on real hardware) beyond the bare cutout, landing content on the real pixels that
  flank it — the same technique other notch utilities use, and why their pills read as a
  bit wider than the bare camera bump. The hover hit-region was widened to match, so
  hovering directly over the now-visible bars/artwork actually opens the notch.

### Added
- **Real audio visualizer (opt-in).** The collapsed notch's audio bars can now show a
  genuine frequency-band visualization of whatever's actually playing, captured via
  ScreenCaptureKit and reduced to 4 bands with a real-time FFT (Accelerate/vDSP). Off by
  default: it requires granting **Screen & System Audio Recording** permission — the same
  category Zoom/OBS use — materially heavier than anything else Islet asks for, so it's
  gated behind its own Settings toggle rather than ever being assumed. Falls back to the
  previous non-audio-reactive animation when off or not yet authorized, so the layout
  never shifts based on whether it's enabled. While capturing, macOS shows its standard
  screen-recording indicator — disclosed in the Settings toggle's own description.
- **Quick Note.** A single persistent scratchpad, the same idea as macOS's own Quick
  Note — always one click away, autosaves as you type, toggleable like every other
  feature.
- **Outside-click dismiss.** Clicking away from an open notch now consumes that click
  instead of passing it through to whatever's underneath, via a transparent
  screen-spanning shield window that only goes up while the notch is actually expanded.
- **`swift run IsletProbe --visualizer`** — prints live frequency-band levels once a
  second, for confirming the visualizer against actually-playing audio.

### Known limitations
- **Granting Screen Recording doesn't survive a rebuild.** Islet is ad-hoc signed, so its
  code hash changes every time it's rebuilt, and macOS keys the permission to that hash —
  a grant given to one build won't apply to the next one. If the visualizer stops working
  after rebuilding, re-grant it in System Settings → Privacy & Security → Screen & System
  Audio Recording (removing the stale Islet entry first, if present). A stable Developer
  ID signature would fix this permanently and is already on the roadmap.

[0.1.0-beta.3]: https://github.com/Lucca-H/islet/releases/tag/v0.1.0-beta.3

## [0.1.0-beta.2] — 2026-07-20

### Added
- **Now Playing rebuilt on distributed notifications.** Music and Spotify each broadcast
  playback changes with full metadata, needing no entitlement and no permission prompt.
  Push-based, so the notch updates instantly. AppleScript fills the gaps (launch state,
  cover art, transport controls); metadata keeps flowing even if Automation is declined.
- **Liquid Glass UI.** The notch renders through AppKit's native `NSGlassEffectView`
  (macOS 26's real glass material, bridged into SwiftUI) — the same material at every
  size, never swapping color as it resizes. Buttons use the system `.glass` style and
  Settings has a bespoke glass-material slider.
- **Notch style setting.** Settings → Notch → Notch style switches the whole surface
  between Liquid Glass and a solid opaque black, matching the physical bezel.
- **`IsletProbe`** — a diagnostic target (`swift run IsletProbe`) that prints what Now
  Playing resolves once per second, for troubleshooting detection.
- **Live activities.** A subtle, brief widening of the collapsed pill (not a full expand)
  hints at background events — a track starting, a file added to the shelf, a new
  clipboard capture — and never fires while the notch is already open or hovered.
  Replaces the previous full-open pulse on track change.

### Fixed
- Now Playing returned nothing at all. Three separate causes: AppleScript rejects the
  variable name `st` (parsed as the ordinal "1st"), which broke every metadata query;
  the backup poll wiped out good notification data whenever Automation was unavailable;
  and `MediaRemote` — the intended source — turned out to be unavailable entirely (below).
- Liquid Glass dropped out when switching notch tabs, caused by nesting an
  `NSGlassEffectView` (the selected tab chip) inside the panel's own glass, and by
  hosting SwiftUI content inside `NSGlassEffectView.contentView`. Glass is now a
  background layer and the chip is a plain translucent capsule.
- The notch's color visibly snapped darker on every expand, then — after a first
  attempted fix — showed no transparency at all. Three compounding causes, in order
  found: a structural swap between an opaque fill and a differently-shaped glass view
  (which SwiftUI can't animate across); fixing that by leaving a permanent opaque black
  layer sitting under a permanent glass layer, which made the glass refract its own
  black instead of the desktop and read as solid regardless of its own opacity; and,
  once real transparency was working, the collapsed pill needed to stay solid black
  (matching the physical hardware bezel) rather than adopt the glass material too. The
  black layer's opacity now genuinely reaches 0 only once actually expanded, fading out
  as the glass fades in — both permanently-present views, only opacity animating.
- The Settings sliders' solid accent fill covered the glass track. The fill is now
  translucent and the thumb is itself glass.

### Changed
- **Minimum macOS raised to 26 (Tahoe).** `NSGlassEffectView` doesn't exist before it;
  there's no fallback UI for older systems.
- Now Playing no longer needs an Automation permission prompt.

### Known limitations
- **Browser/web audio is not supported.** The only system-wide API for it (`MediaRemote`)
  is gated to Apple-signed binaries on macOS 26. Verified directly: identical code returns
  30 populated keys from Apple's `swift-frontend` and an empty dictionary from an
  ad-hoc-signed `.app`, at the same instant with the same track playing — and neither
  entitlements nor proper bundling changes it. Islet still tries it first and will use it
  automatically if a build ever gains access, then falls back to Music/Spotify.
- Artwork and transport controls need Automation permission; track metadata does not.
- Investigated mirroring real system notifications (any app, not just Islet's own
  events) via the classic `DistributedNotificationCenter` technique other notch utilities
  use — confirmed live that Apple no longer delivers a payload through it. The remaining
  fallback (reading Notification Center's on-disk database) requires Full Disk Access and
  exposes every app's notification content, so it was deliberately not implemented.

[0.1.0-beta.2]: https://github.com/Lucca-H/islet/releases/tag/v0.1.0-beta.2

## [0.1.0-beta.1] — 2026-07-20

First public beta. 🎉

### Added
- **Now Playing** — detects Apple Music and Spotify playback via AppleScript, with
  album art, metadata, and play/pause/next/previous transport controls. Collapsed notch
  peeks album art and a live audio indicator; auto-opens briefly on track change.
- **Drop Shelf** — drag files onto the notch to stash them, drag them back out anywhere,
  double-click to reveal in Finder. Persists across launches.
- **Clipboard History** — rolling history of copied text and images, click to re-copy,
  with password/transient filtering.
- **Settings** — notch behavior (hover/click, delays, haptics), size & shape (width,
  height, corner radius, closed-height boost), per-display targeting, feature toggles,
  clipboard options, and launch-at-login.
- Menu-bar item with Settings and Quit.
- Works on notchless displays as a floating handle.
- Built-in self-check runner (`swift run IsletChecks`) and swift-testing suite.

### Known limitations
- Ad-hoc signed, **not notarized** — first launch requires right-click → Open (or clearing
  the quarantine attribute).
- Now Playing supports Apple Music and Spotify only (system-wide MediaRemote is gated by
  Apple on recent macOS and intentionally not used).
- Dragging a file *directly* onto a collapsed notch does not auto-open it yet; hover to
  open, then drop. (Tracked for a future release.)
- Requires macOS 14 or later.

[0.1.0-beta.1]: https://github.com/Lucca-H/islet/releases/tag/v0.1.0-beta.1
