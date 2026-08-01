# Changelog

All notable changes to Islet are documented here. This project follows
[Semantic Versioning](https://semver.org) and [Keep a Changelog](https://keepachangelog.com).

## [0.1.0-beta.8] — 2026-07-31

### Fixed
- **The click shield absorbed nothing at all.** It was a transparent window whose view
  drew nothing, and AppKit hit-tests windows against rendered alpha rather than their
  frame — fully transparent pixels aren't just invisible, they're absent to the event
  system, so every click fell straight through to the app underneath. The shield now
  paints at 1/255 alpha, the lowest value that survives the 8-bit backing store. The
  mouse-up deferral and `acceptsFirstMouse` work from beta.6 were both correct and both
  unreachable behind this.
- **Its safety-net timeout couldn't fire when it was needed.** The 1s timer that
  releases a stuck shield was scheduled in the default run-loop mode, but a click held
  long enough to need it has put the run loop in event-tracking mode. Added in
  `.common` instead.
- **The visualizer showed audio from other apps.** `SCStream` captures the whole system
  mix, so a video playing in a browser over Spotify was summed into the same FFT and the
  bars described both at once — next to a track title that only referred to one of them.
  Capture is now scoped by `SCContentFilter` to the app Now Playing has resolved, and
  the stream restarts when that changes (a filter is fixed for a stream's lifetime). If
  the player isn't in `SCShareableContent` — it only lists apps with on-screen windows,
  so a minimized player can be missing — it falls back to the system mix rather than
  going dark.
- **The collapsed pill's album art was jammed against the pill's edge.** Two causes.
  `NotchShape` flares its top shoulders *outward*, so the pill's straight body edge sits
  8pt inside the frame — the art's 10pt leading padding was therefore buying 2pt of
  visible margin. And the art was sized off the pill's *height* when the binding
  constraint is the strip of real pixels beside the camera cutout: on a 16" that
  produced a 23.6pt cover with ~2pt either side against 7.2pt above and below. The art
  is now centred in that strip and bounded by it, so its left and right margins are
  equal by construction. A square in a box narrower than it is tall can't have four
  equal margins, so the checks bound the remaining imbalance rather than pretending it
  can be tuned away.
- **The expanded panel's album art sat visibly off-centre.** The panel's tighter bottom
  inset exists because "every tab ends in a footer row" — true of Shelf, Clipboard and
  Quick Note, but not of Now Playing, which is the one tab whose content is a square
  sized to fill the content box's full height. Its only breathing room was therefore the
  panel inset itself: 22pt above the cover and 10pt below it. Footerless tabs now take a
  symmetric inset instead. `ExpandedNotchView.contentHeight` is consequently
  tab-dependent, and the checks assert the footerless tab never spends *more* vertical
  padding than a footer tab rather than that the two match.

### Changed
- **The collapsed pill's album art is ~21% larger** (19.8pt → 24pt). Both of its bounds
  had to move: the strip of real pixels beside the cutout went 36pt → 40pt, and the
  height share went 0.62 → 0.75, since on a 32pt notch the height term was the binding
  one and widening the strip alone would have bought nothing there. Its clearance comes
  out even on all four sides on a 32pt notch, rather than 4pt against 6pt. On a physical
  notch this widens the collapsed pill itself by 8pt, since the pill is the cutout plus
  two strips — that's the actual cost of a bigger peek. Notchless displays are unchanged
  in width.
- **The expanded album art is larger** — about 12% on a notchless display and 4% on a
  notched one. Two different limits were binding. Its width cap was a flat fraction of
  the song column, and because a fraction applies uniformly it had to be set by the
  narrowest panel the sliders allow, leaving the art short of the space actually going
  spare at every other size; the metadata column's minimum width is now enforced
  directly, so the art can take exactly what's left and the fraction is just taste on
  top. On a notched Mac the art is bound by panel *height* instead — it already equalled
  the content box exactly — so the footerless tab's vertical inset is tighter as well,
  trading padding for cover. The rest of the layout is unchanged: the guard still sweeps
  every width/height combination, and the metadata column now lands exactly on its floor
  at the tightest setting rather than by a hand-derived margin.
- Removed the claim, from both the README and the Settings copy, that the visualizer is
  a way to detect browser audio. Capture only ever ran while Music or Spotify was
  playing, so it was never true; scoping the filter now makes it explicitly false.

## [0.1.0-beta.7] — 2026-07-30

### Changed
- **Minimum macOS lowered from 26 (Tahoe) to 13 (Ventura).** Islet was pinned to Tahoe
  for exactly one reason — `NSGlassEffectView`, the Liquid Glass material — and that
  turned out to be the only API in the whole app that needed it. Ventura is the new
  floor because it's where `ScreenCaptureKit` gained audio capture, which the real
  audio visualizer depends on; below that the feature would have to be cut rather than
  degraded.
- **Liquid Glass is now offered only where it exists.** On macOS 13–15 the Settings →
  Notch → **Notch style** picker shows Solid alone, the default flips to Solid, and a
  persisted `liquidGlass` value (from a synced defaults domain, or a disk moved to
  older hardware) is coerced to Solid at load. The option is hidden rather than mapped
  onto a vibrancy blur, since that is a visibly different material and labelling it
  "Liquid Glass" would make the setting a lie. Every other feature is unchanged.
- `GlassBackground` no longer names `NSGlassEffectView` outside an availability check.
  Its `NSViewType` is now plain `NSView` and the style argument is Islet's own
  `GlassStyle` enum — a macOS 26 type in a property or signature is resolved at compile
  time no matter what runtime branch guards it, which is what forced the deployment
  target up in the first place. Chrome that is glass unconditionally (the Settings
  slider) falls back to `NSVisualEffectView`.
- **README audited against the code.** It still described three tabs (there are four),
  a 32-band FFT (96 since beta.6), hover-only expansion (click has been an option for a
  while), and made no mention of the progress bar or of Screen & System Audio Recording
  in the permissions table. Added a Requirements section for the new version floor and a
  note on the ad-hoc-signing permission trap.
- The audio visualizer's permission prompt hangs off a custom `Binding` instead of
  `onChange(of:initial:_:)`, whose two-closure form is macOS 14+ and whose one-closure
  form is deprecated there.

## [0.1.0-beta.6] — 2026-07-26

### Added
- **Song progress bar** in Now Playing, with elapsed and remaining times. Position is
  read by AppleScript (neither player pushes it), so the bar extrapolates between the
  3-second samples rather than stepping, and corrects itself each time a real reading
  lands. Tracks that report no duration — streams, some local files — hide the bar
  instead of showing an empty one, and it degrades to a bare bar (then to nothing) on
  panels too short to fit the timestamps.
- **Live activities can grow sideways instead of dropping down.** Settings → Notch →
  **Live activity direction** switches a peek (new song, file added, something copied)
  between the existing drop-down and new **Left** / **Right** modes, which pin the
  pill's opposite edge and extend it into the menu bar beside the notch — no vertical
  growth, so it stays inside the menu-bar band. Defaults to **Down**, unchanged.

### Fixed
- **Album art is sharper.** Two causes. Spotify's `artwork url of current track`
  usually returns the 300px thumbnail — barely enough for the panel's art at 2x, and
  soft at the larger size settings; since Spotify encodes the dimension in the image ID,
  Islet now rewrites it to the 640px variant of the same asset (falling back to the
  original if that ever stops resolving). Separately, `NSImage` derives its size from
  DPI metadata, so a 600px cover tagged at 144dpi reported 300pt and could be drawn
  softer than the bitmap it held; artwork now reports its true pixel size. The second
  fix applies to Apple Music too.
- **Peeks no longer overshoot.** The pill widened by a fixed 260pt whatever it was
  showing, so "Copied an image" opened exactly as far as a long song title — visibly
  too far for short text. It now measures the row and opens only as wide as that
  needs, still capped at what the window can draw (long titles truncate as before) and
  floored at the collapsed width.
- **Outside-click dismissal no longer eats unrelated clicks.** The screen-spanning
  shield went up whenever the notch was expanded — including in hover mode, where the
  notch closes on pointer exit but stays open for `hoverCloseDelay` first. Moving off
  the notch and immediately clicking something else landed on the shield instead of the
  target. The shield now only goes up in **click** trigger mode, where a dismissing
  click is actually a thing that exists.
- **Dismissing clicks are swallowed whole.** The shield stood down during the mouse-
  *down*, leaving the matching mouse-*up* to reach whatever was underneath — so the
  click was halved rather than consumed, and anything acting on mouse-up still fired.
  It now stays up until the click completes. Also sets `acceptsFirstMouse`, without
  which clicks arriving while Islet is inactive (i.e. essentially all of them) weren't
  reliably delivered to the shield at all.
- **Treble bands read far too low against bass.** Music has a roughly `1/f` spectrum,
  so an uncorrected FFT display is nearly all bass with the top bands hovering near
  zero. Bands are now tilted by `f^0.3` before normalization, lifting the top end
  without flattening the slope entirely — a full `f^0.5` correction moves the loudest
  band to treble, and since gain control normalizes against the loudest band, that
  scales bass against treble and makes bass disappear instead.
- **Mini visualizer bars rendered alternately rounded and squared.** As an `HStack` of
  capsules each bar was its own layer, and each layer's frame snaps to the backing pixel
  grid independently — with the bars' stride that snapping alternated, so every other
  bar's rounded caps rasterized fully while its neighbour's flattened. Drawn in a single
  `Canvas` now, like the circular visualizer, which removes the per-layer snapping.
- **Circular visualizer bars rendered at inconsistent widths.** Each was its own
  rotated view, so ~96 layers were antialiased independently: bars whose angle landed
  near the pixel grid came out crisp and thin while diagonal ones smeared over an extra
  pixel and read as fatter. The whole ring is now drawn in a single `Canvas`, so every
  bar is rasterized in one pass from the same geometry — which is also far less work per
  frame than 96 animated views.
- **The lowest frequency bands were permanently dead.** A band narrower than one FFT
  bin was skipped outright and left pinned at zero — which already silently killed the
  bottom of the range at 32 bands, and would have wiped out a whole run of them at 96.
  Such a band now reads whichever bin it falls in.
- **The mini bars disagreed with the circular visualizer.** They averaged 8 bands per
  bar, burying each peak under its quiet neighbours; they now take each bucket's peak.
- **Gain control now holds at every audible level.** It had a floor on the reference,
  which doubles as the point where volume-independence stops: below it the reference
  stops adapting and levels track amplitude again. That regime was reachable at
  ordinary reduced volume — invisible in the circular visualizer, whose peak clamp
  saturates the top bars and hides it, but plainly visible in the linearly-mapped mini
  bars, which is why only one of the two looked broken. Silence is now handled by
  zeroing the output rather than by flooring the reference.
- **The visualizer no longer tracks playback volume.** Band levels were divided by a
  fixed constant, which made the display an output-volume meter: turning Spotify's own
  volume down shrank the bars even though the music hadn't changed, and quietly-mastered
  tracks barely moved. Levels are now normalized against a slowly-adapting reference, so
  they follow the spectrum's shape rather than its amplitude. A floor on that reference
  keeps automatic gain from amplifying silence into a full-scale display.

### Changed
- **Circular visualizer is far more finely grained** — 96 bands instead of 32, drawn
  as 1.5pt hairlines, for a ring of fine ticks rather than chunky blocks. The FFT
  window doubled to 2048 points to actually resolve that many bands at the low end.
- **Now Playing columns are laid out by share, not by content.** The song (art +
  metadata + transport) takes ~65% of the panel and is pinned left; the visualizer gets
  the rest and is centred in it at 80% of that width. Previously the visualizer was
  sized as a fraction of the album art and simply followed wherever the metadata column
  happened to end, so it was never actually centred in its space. The visualizer's
  region is sized back from the square itself, so when panel height binds the leftover
  width returns to the song column instead of sitting as dead space beside the ring —
  which is what left the right margin wider than the left.
- **Mini visualizer is 6 bars** (from 4), in a proportionally wider pill.
- **Circular visualizer bars reach full brightness earlier**, at 55% level rather than
  only at the very top of the range. Under the old linear ramp only the single tallest
  bar was ever fully lit, so the ring read as dull.
- **Circular visualizer toned down** — less peak exaggeration (1.7x → 1.25x), slightly
  shorter bars, and a gentler opacity ramp. The old boost existed to compensate for raw
  magnitudes reading flat; with gain control doing that upstream it was double-counting
  and left the ring near-saturated.

[0.1.0-beta.8]: https://github.com/Lucca-H/islet/releases/tag/v0.1.0-beta.8
[0.1.0-beta.7]: https://github.com/Lucca-H/islet/releases/tag/v0.1.0-beta.7
[0.1.0-beta.6]: https://github.com/Lucca-H/islet/releases/tag/v0.1.0-beta.6

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
