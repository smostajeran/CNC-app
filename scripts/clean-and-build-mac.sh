#!/usr/bin/env bash
# Wipe Quill build products and do a fresh macOS build + launch.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Quit any running Quill"
killall Quill 2>/dev/null || true
sleep 0.5

echo "==> Removing build artifacts"
rm -rf \
  "$ROOT/build" \
  "$ROOT/DerivedData" \
  "$ROOT/CNCCore/.build" \
  "$ROOT/CNCCore/.swiftpm" \
  "$ROOT/.swiftpm" \
  "$ROOT/Quill.xcodeproj"

# Xcode’s default DerivedData can keep a stale Quill.app
if [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]]; then
  find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 1 -type d -name 'Quill-*' -exec rm -rf {} +
fi

# Old installs under /Applications can shadow a fresh debug build in Launchpad/Dock.
if [[ -d "/Applications/Quill.app" ]]; then
  echo "==> Note: /Applications/Quill.app still exists — this script launches the repo Debug build, not that copy."
fi

echo "==> Fresh CNCCore resolve"
swift package --package-path CNCCore resolve

echo "==> Fresh build"
"$ROOT/scripts/build-mac.sh"

APP="$ROOT/build/DerivedData/Build/Products/Debug/Quill.app"
echo "==> Launching Debug build (not /Applications)"
open -n "$APP"
echo "Confirm header shows: 1.3 (8) · $(git rev-parse --short HEAD)"
