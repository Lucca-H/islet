# Contributing to Islet

Thanks for your interest! Islet is a young beta, so there's plenty to do.

## Getting started

```bash
git clone https://github.com/Lucca-H/islet.git
cd islet
swift build
swift run IsletChecks     # fast logic checks — no Xcode required
swift run IsletProbe      # live Now Playing diagnostic (prints what it resolves)
./scripts/build_app.sh    # build a runnable Islet.app
open build/Islet.app
```

`IsletProbe` also accepts:

- `--synthetic` — injects a fake Music notification, so the detection path can be
  exercised without anything actually playing.
- `--visualizer` — starts the real capture engine and prints frequency-band levels
  once a second, for checking the visualizer against actually-playing audio.

Note that `IsletProbe` is a separate bundle identifier from Islet, so macOS tracks its
Screen Recording permission separately — `--visualizer` will report "not authorized"
until the probe itself is granted access, independently of the app.

## Debugging the audio visualizer

Capture failures are otherwise silent, so the engine records what it's doing to
`UserDefaults`:

```bash
defaults read com.dynamicisland.islet visualizerDebugLog
```

The same log is in the app under Settings → Notch → Audio visualizer → *Diagnostic
log*, with a Copy button.

Because Islet is ad-hoc signed, its code hash changes on **every rebuild**, and macOS
pins Screen Recording permission to that hash — so a grant stops applying after any
rebuild, and the leftover "Islet" row in System Settings refers to a binary that no
longer exists. Settings has a *Reset Permission & Quit Islet…* button for this; it runs
`tccutil reset ScreenCapture com.dynamicisland.islet`. A stable Developer ID signature
would remove the problem entirely.

You need macOS 26 (Tahoe) or later and the Swift toolchain. Command Line Tools are sufficient for
building and the self-checks; the full `swift test` suite needs Xcode.

## Project layout

| Path | What |
|------|------|
| `Sources/IsletCore/` | All app logic: notch window & controller, features, settings, view models. |
| `Sources/Islet/` | The thin `NSApplication` entry point. |
| `Sources/IsletChecks/` | Dependency-free assertion runner. |
| `Tests/IsletTests/` | swift-testing suite (CI). |
| `scripts/` | Build, icon, and release helpers. |

## Before opening a PR

1. `swift build` is warning-free.
2. `swift run IsletChecks` passes.
3. If you touched pure logic, add a matching check in `Sources/IsletCore/SelfChecks.swift`
   **and** a test in `Tests/IsletTests/` (keep them in sync).
4. Keep commits focused; describe user-facing changes in `CHANGELOG.md` under *Unreleased*.

## Style

- Match the surrounding code — small, documented types; `@MainActor` for anything touching UI.
- Prefer clarity over cleverness. Comment the *why*, not the *what*.

## Reporting bugs

Open an issue with your macOS version, whether your Mac has a physical notch, and steps to
reproduce. Logs are available in Console.app under the `com.dynamicisland.islet` subsystem.
