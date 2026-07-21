<div align="center">

<img src="docs/assets/icon.png" width="128" alt="Islet icon" />

# Islet

**Turn your Mac's notch into a live hub for media, files, and your clipboard.**

[![CI](https://github.com/OWNER/islet/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/islet/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/OWNER/islet?include_prereleases&sort=semver)](https://github.com/OWNER/islet/releases)
![Platform](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![License](https://img.shields.io/badge/license-MIT-blue)

<img src="docs/assets/banner.png" width="720" alt="Islet banner" />

</div>

> **Beta software.** Islet is an independent, open-source project inspired by notch utilities
> like NotchNook. It is not affiliated with or endorsed by them.

---

## Features

Hover the notch and it expands into a compact panel with three tabs:

### 🎵 Now Playing
- Detects the current track from **Apple Music** and **Spotify**.
- Album art, title, and artist, with **play / pause / next / previous** controls.
- When collapsed, the notch peeks the album art and a live audio-bars indicator.
- The notch briefly auto-opens when a new track starts.

### 🗂 Drop Shelf
- Drag any file onto the notch to stash it on a temporary shelf.
- Drag files back out into Finder, Mail, Slack — anywhere that accepts a drop.
- Double-click to reveal in Finder; the shelf persists between launches.

### 📋 Clipboard History
- Keeps a rolling history of copied **text and images**.
- Click any entry to copy it back to the pasteboard.
- Skips passwords and transient copies from password managers (configurable).

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
1. Grab `Islet.app.zip` from the [latest release](https://github.com/OWNER/islet/releases).
2. Unzip and move **Islet.app** to `/Applications`.
3. Because the beta is **ad-hoc signed (not notarized)**, right-click the app → **Open** the
   first time, or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Islet.app
   ```
4. On first launch, grant **Automation** permission when prompted (needed to read Music/Spotify).

### Build from source
Requires macOS 14+ and either Xcode or the Swift toolchain (Command Line Tools are enough).
```bash
git clone https://github.com/OWNER/islet.git
cd islet
./scripts/build_app.sh release
open build/Islet.app
```

---

## Permissions

| Permission | Why | When |
|-----------|-----|------|
| **Automation** (Music / Spotify) | Read the currently playing track and send transport commands. | Prompted on first playback detection. |
| **Accessibility** | Not required. | — |

Islet does **not** use the private MediaRemote framework — Apple gated it behind a private
entitlement in recent macOS releases — so Now Playing is provided via AppleScript for the two
most common players. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

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
