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

`IsletProbe` also accepts `--synthetic`, which injects a fake Music notification so the
detection path can be exercised without anything actually playing.

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
