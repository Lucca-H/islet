# Changelog

All notable changes to Islet are documented here. This project follows
[Semantic Versioning](https://semver.org) and [Keep a Changelog](https://keepachangelog.com).

## [0.1.0-beta.5] — 2026-07-21

### Changed
- **Now Playing is Apple Music and Spotify only.** Browser/web audio support is
  dropped outright rather than half-present: the private `MediaRemoteBridge` — which
  could never return data for a third-party build on macOS 26 — has been **deleted**,
  along with the "show bars for any detected audio" fallback. Islet no longer depends
  on a private API at all for Now Playing, and no longer lights up for arbitrary
  browser tabs or notification sounds.
- **Buttons are outlined rather than filled.** The system `.glass` style filled each
  control's whole background, which competed with the album art beside it. New
  `OutlineButtonStyle` / `OutlineTextButtonStyle` use a thin stroke, brightening on
  hover and dimming on press instead of swapping background colour.
- **Settings button enlarged** (30pt, from 24pt).
- **Album art enlarged** — up to 140pt from 96pt, and now sized from the actual
  available height, so a smaller "Expanded height" setting shrinks it instead of
  overflowing the panel.
- **Now Playing relaid out** into three balanced columns: art, track identity +
  transport controls, and the visualizer.
- Audio capture again runs only while a track is actually playing. That gate was
  briefly removed while browser support was still being attempted (where it wrongly
  disabled the one thing that *could* see web audio); with Now Playing scoped to
  Music/Spotify it's correct again, and keeps the screen-recording indicator off
  whenever music isn't playing.

### Added
- **Circular spectrum visualizer** in the expanded Now Playing panel — one radial bar
  per frequency band, bass at 12 o'clock sweeping clockwise through treble. Band count
  raised 4 → 32 for real detail; the collapsed pill's mini bars downsample the same
  single FFT via `compactBars(count:)` rather than running a second analysis.
- **Diagnostics for the audio pipeline.** Capture failures were entirely silent —
  `SCStream` errors only reached `os_log`, which isn't readable back without extra
  permissions, so the sole symptom was dead bars. The engine now records what it's
  doing to `UserDefaults` (`visualizerDebugLog`), surfaced in Settings → Notch →
  Audio visualizer with a Copy button, plus a *Reset Permission & Quit Islet…* button
  for the ad-hoc-signing permission problem below. `IsletProbe` also gained
  `--visualizer`, which prints live frequency-band levels.

### Fixed
- **The audio visualizer never started at all.** `AppDelegate` subscribed to
  `nowPlaying.$info`, mapped it to `isPlaying`, then discarded that value and re-read
  `nowPlaying.info` inside the sink. `@Published` emits in `willSet`, so the stored
  property still held the *previous* value: at the exact moment playback began the
  gate read "not playing" and called `stop()` instead of `start()`. It could never
  have worked.
- **Capture stalled silently after a minute or two.** `SCStream` was created with
  `delegate: nil`, so a session dying internally was invisible — `isCapturing` stayed
  stuck at `true` with nothing to catch or restart it. There's now a real
  `SCStreamDelegate`, plus an independent buffer-arrival watchdog that forces a
  restart if no audio arrives for 4s (some failure modes never call the delegate at
  all). The retry loop also no longer retires itself on first success, which would
  have left a failed watchdog restart with nothing to recover it.
- **Circular visualizer bars didn't sit on the ring.** They were positioned manually
  inside a `GeometryReader` via `.position()`, putting bars and ring in subtly
  different coordinate spaces. Now uses the standard radial pattern — lay out centred,
  `.offset` outward, then `.rotationEffect` — which is exact because `.offset` leaves
  the layout frame centred for the rotation to pivot on.
- **Clipboard image thumbnails overflowed their row**, painting over the adjacent
  label. `.clipShape` was applied before the `.frame`, so a copied screenshot was
  scaled to its natural size, clipped there, and only then given a 26pt layout frame.
- **Now Playing could overflow at narrow widths.** Album art and the visualizer are
  both squares sized from panel *height*, flanking a metadata column whose transport
  row can't shrink; with no width term, the Settings sliders could collapse it (at
  420×210 the metadata column got 12pt; at 420×340 it went negative). Art is now
  capped against width too, and the panel/layout constants are shared with a
  regression check that sweeps the entire slider range.
- Transport button outlines used `.stroke`, which centres the line on the path and
  lets half its width bleed outside the button's bounds — visible as slight
  misalignment. Now `.strokeBorder`. `play.fill` is also nudged 1.5pt right, since a
  play triangle's visual mass sits left of its geometric centre.
- Footer rows (item count / last-edited plus a button) floated too far above the
  panel's bottom edge; the bottom inset is now a deliberately tighter 10pt.

### Known limitations
- **Screen Recording permission does not survive a rebuild.** Islet is ad-hoc signed,
  so it has no stable code identity — macOS pins the grant to the exact binary hash,
  and the leftover "Islet" row in System Settings refers to a build that no longer
  exists (toggling it there does nothing). Use the *Reset Permission & Quit Islet…*
  button, or `tccutil reset ScreenCapture com.dynamicisland.islet`. A Developer ID
  signature would remove this entirely.

## [0.1.0-beta.4] — 2026-07-21

### Fixed
- **The audio visualizer could go permanently unregistered for Screen Recording
  permission**, showing "Not authorized" indefinitely with no path to fix it short of
  toggling the Settings switch off and back on. `CGRequestScreenCaptureAccess()` — not
  just preflighting — is what actually registers Islet with TCC and shows the system
  prompt the first time; it was only being called from the Settings toggle's
  `onChange`, which fires on a *transition*. Since `audioVisualizerEnabled` persists
  across launches, the common case is opening Settings and seeing the toggle already
  on — no transition, `onChange` never fires, `requestAccess()` never called, Islet
  never registered for that build's hash. `AudioVisualizerEngine.start()` now calls
  `requestAccess()` itself on every attempt (the retry loop already added in
  beta.3 means this costs nothing extra), closing the gap regardless of how the
  toggle got to "on."
- Confirmed live, end-to-end, that `NowPlayingManager` itself has no bugs: run in
  isolation against real Spotify playback it resolved title/artist/artwork in under a
  second, both via the reactive notification path and the AppleScript catch-up poll.
  Automation permission was also confirmed *not* to be gated for AppleScript spawned
  via `/usr/bin/osascript` on this setup — a completely fresh, never-before-seen app
  queried Spotify's current track instantly with no prompt at all.

[0.1.0-beta.5]: https://github.com/Lucca-H/islet/releases/tag/v0.1.0-beta.5
[0.1.0-beta.4]: https://github.com/Lucca-H/islet/releases/tag/v0.1.0-beta.4

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
