#!/usr/bin/env bash
#
# Builds Islet.app from the SwiftPM executable.
# Usage: ./scripts/build_app.sh [debug|release]   (default: release)
#
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Islet.app"
CONTENTS="$APP/Contents"

echo "==> Building Islet ($CONFIG)…"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/Islet"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "!! Executable not found at $BIN_PATH" >&2
  exit 1
fi

echo "==> Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_PATH" "$CONTENTS/MacOS/Islet"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "==> Building app icon…"
ICON_PNG="$ROOT/build/icon_1024.png"
if [[ ! -f "$ICON_PNG" ]]; then
  swift "$ROOT/scripts/make_icon.swift" "$ICON_PNG"
fi

ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for size in 16 32 64 128 256 512 1024; do
  sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
done
# Retina (@2x) variants.
cp "$ICONSET/icon_32x32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$ICONSET/icon_64x64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$ICONSET/icon_256x256.png" "$ICONSET/icon_128x128@2x.png"
cp "$ICONSET/icon_512x512.png" "$ICONSET/icon_256x256@2x.png"
cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
rm -f "$ICONSET/icon_64x64.png" "$ICONSET/icon_1024x1024.png"
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

echo "==> Ad-hoc code signing…"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
  echo "   (codesign skipped — app will still run locally)"

echo "==> Done: $APP"
