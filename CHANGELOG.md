# Changelog

All notable changes to Islet are documented here. This project follows
[Semantic Versioning](https://semver.org) and [Keep a Changelog](https://keepachangelog.com).

## [0.1.0-beta.2] — 2026-07-20

### Added
- **Now Playing rewritten for system-wide detection.** Replaces AppleScript polling with
  the private `MediaRemote` framework (the same feed behind Control Center's widget):
  Apple Music, Spotify, and web audio playing in any browser tab (Safari, Chrome,
  anything using the Media Session API), with real embedded album art and the source
  app's name/icon.
- **Liquid Glass UI.** The expanded panel now renders through AppKit's native
  `NSGlassEffectView` (macOS 26's real glass material, bridged into SwiftUI), buttons use
  the system `.glass` style, and Settings has a bespoke glass-material slider.
- **Live activities.** A subtle, brief widening of the collapsed pill (not a full expand)
  hints at background events — a track starting, a file added to the shelf, a new
  clipboard capture — and never fires while the notch is already open or hovered.
  Replaces the previous full-open pulse on track change.

### Changed
- **Minimum macOS raised to 26 (Tahoe).** `NSGlassEffectView` doesn't exist before it;
  there's no fallback UI for older systems.
- Now Playing no longer needs an Automation permission prompt.

### Known limitations
- Now Playing and the glass panel both rely on undocumented, private system frameworks
  (`MediaRemote.framework`, `NSGlassEffectView`). Widely used by similar menu-bar apps,
  but Apple could change or restrict either in a future release; Now Playing degrades to
  "nothing playing" rather than crashing if that happens.
- Investigated mirroring real system notifications (any app, not just Islet's own
  events) via the classic `DistributedNotificationCenter` technique other notch utilities
  use — confirmed live that Apple no longer delivers a payload through it. The remaining
  fallback (reading Notification Center's on-disk database) requires Full Disk Access and
  exposes every app's notification content, so it was deliberately not implemented.

[0.1.0-beta.2]: https://github.com/OWNER/islet/releases/tag/v0.1.0-beta.2

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

[0.1.0-beta.1]: https://github.com/OWNER/islet/releases/tag/v0.1.0-beta.1
