#!/usr/bin/env bash
#
# Builds Islet.app and packages a distributable zip + checksums into build/dist/.
# Usage: ./scripts/make_release.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/build/dist"

"$ROOT/scripts/build_app.sh" release

rm -rf "$DIST"; mkdir -p "$DIST"

echo "==> Zipping app…"
# ditto preserves the bundle's code signature and resource forks.
ditto -c -k --sequesterRsrc --keepParent "$ROOT/build/Islet.app" "$DIST/Islet.app.zip"

echo "==> Writing checksums…"
( cd "$DIST" && shasum -a 256 Islet.app.zip > SHA256SUMS.txt )

echo "==> Release artifacts:"
ls -lh "$DIST"
cat "$DIST/SHA256SUMS.txt"
