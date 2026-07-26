<div align="center">

<img src="docs/assets/icon.png" width="128" alt="Islet icon" />

# Islet

**Turn your Mac's notch into a live hub for media, files, and your clipboard.**

[![CI](https://github.com/Lucca-H/islet/actions/workflows/ci.yml/badge.svg)](https://github.com/Lucca-H/islet/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Lucca-H/islet?include_prereleases&sort=semver)](https://github.com/Lucca-H/islet/releases)
![Platform](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![License](https://img.shields.io/badge/license-MIT-blue)

<img src="docs/assets/banner.png" width="720" alt="Islet banner" />

</div>

> **Beta software.** Islet is an independent, open-source project inspired by notch utilities
> like NotchNook. It is not affiliated with or endorsed by them.

---

## Features

Hover the notch and it expands into a real **Liquid Glass** panel with three tabs.

### 🎵 Now Playing
- Detects playback from **Apple Music** and **Spotify** via each app's
  `DistributedNotificationCenter` broadcast — push-based, instant, and requiring no
  permission prompt.
- Large album art, title, artist, and source app, with outlined
  **play / pause / next / previous** controls.
- An optional **circular spectrum visualizer** on the right, driven by a real 32-band
  FFT of the audio actually playing (Settings → Notch → Audio visualizer). Levels are
  gain-normalized, so the bars react to the music rather than to how loud you happen to
  have the volume turned up. Off by
  default: it requires granting Screen & System Audio Recording permission, the
  heaviest ask anywhere in Islet, so it's opt-in only. Capture runs only while a track
  is actually playing, so the system recording indicator isn't up any longer than
  necessary.
- When collapsed, the notch peeks the album art and a live audio-bars indicator.

> **Browser/web audio is not supported, by design.** The only system-wide API for it
> (`MediaRemote`) is gated to Apple-signed binaries on macOS 26 — verified directly:
> identical code returns full data from Apple's own `swift-frontend` and an empty
> dictionary from an ad-hoc-signed app bundle. Rather than ship a private-API
> dependency that can never fire for a third-party build, Islet doesn't attempt it.

### 🗂 Drop Shelf
- Drag any file onto the notch to stash it on a temporary shelf.
- Drag files back out into Finder, Mail, Slack — anywhere that accepts a drop.
- Double-click to reveal in Finder; the shelf persists between launches.

### 📋 Clipboard History
- Keeps a rolling history of copied **text and images**.
- Click any entry to copy it back to the pasteboard.
- Skips passwords and transient copies from password managers (configurable).

### 📝 Quick Note
A single persistent scratchpad — the same idea as macOS's own Quick Note — always one
click away in the notch. Autosaves as you type.

### ✨ Live activities
A subtle, brief widening of the collapsed pill — not a full expand — hints at background
events: a track starting, a file landing on the shelf, something new on the clipboard.
Never fires while you're already looking at the notch.

Pick which way it grows in Settings → Notch → **Live activity direction**: **Down** drops
the pill below the menu bar, while **Left** and **Right** keep it in the menu bar and
extend it sideways out of that edge of the notch.

### 🧊 Liquid Glass throughout
The collapsed notch always stays solid black, blending into the physical hardware
bezel — Liquid Glass reveals itself only once you actually open it, rendered with
AppKit's native `NSGlassEffectView` (macOS 26's real glass material). Buttons use the
system `.glass` style and Settings has a custom glass slider. Prefer fully opaque
instead? Settings → Notch → **Notch style** keeps it solid black in every state.

The collapsed pill is deliberately a bit wider than the bare camera cutout — that gap
has zero real, displayable pixels, so content drawn exactly within it (album art,
audio bars) would be physically invisible, hidden behind the camera housing itself.

### ⚙️ Settings
A full preferences window covering:
- **Notch behavior** — expand on hover or click, open/close delays, haptics.
- **Size & shape** — expanded width/height, corner radius, collapsed height boost.
- **Displays** — built-in only, primary only, or all screens (works on notchless Macs too, as a floating handle).
- **Features** — toggle each feature independently.
- **Clipboard** — history size, image storage, password filtering.
- Launch at login.

---

## Install

### Download (recommended)
1. Grab `Islet.app.zip` from the [latest release](https://github.com/Lucca-H/islet/releases).
2. Unzip and move **Islet.app** to `/Applications`.
3. Because the beta is **ad-hoc signed (not notarized)**, right-click the app → **Open** the
   first time, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Islet.app
   ```
4. No further setup — no permissions to grant for Now Playing.

### Build from source
Requires macOS 26 (Tahoe) or later, and either Xcode or the Swift toolchain (Command Line Tools are enough).
```bash
git clone https://github.com/Lucca-H/islet.git
cd islet
./scripts/build_app.sh release
open build/Islet.app
```

---

## Permissions

| Permission | Why | Needed for |
|-----------|-----|-----------|
| *(none)* | Track title, artist, album, and play state arrive via distributed notifications. | Core Now Playing |
| **Automation** (Music / Spotify) | Reading state at launch, fetching cover art, and sending transport commands. | Artwork + controls |

Islet keeps working if you decline Automation — you'll still get live track metadata from
the notification feed, just without artwork or transport buttons.

Troubleshoot detection with the built-in probe:

```bash
swift run IsletProbe        # prints what Now Playing resolves, once per second
```

---

## Development

```bash
swift build              # build everything
swift run IsletChecks    # run the built-in self-checks (no Xcode needed)
swift test               # run the swift-testing suite (requires Xcode)
./scripts/build_app.sh   # assemble Islet.app
```

The project is a Swift Package:

- **`IsletCore`** — all app logic (notch window, features, settings, view models).
- **`Islet`** — the thin `NSApplication` executable.
- **`IsletChecks`** — a dependency-free assertion runner (Command Line Tools ship no XCTest).
- **`IsletTests`** — the swift-testing suite used in CI.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for a tour of the code.

---

## Roadmap

- [ ] Notarized, Developer ID-signed builds
- [ ] Drag-to-open while a Finder drag is in progress
- [ ] Scrubbable playback progress + volume
- [ ] Calendar / timer / battery widgets
- [ ] Custom accent colors and themes

Known beta limitations are tracked in [CHANGELOG.md](CHANGELOG.md).

---

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © Islet contributors.
