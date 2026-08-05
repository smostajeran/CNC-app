#!/usr/bin/env bash
# Wipe Quill build products and do a fresh macOS build + launch.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

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

echo "==> Fresh CNCCore resolve"
swift package --package-path CNCCore resolve

echo "==> Fresh build"
"$ROOT/scripts/build-mac.sh"

APP="$ROOT/build/DerivedData/Build/Products/Debug/Quill.app"
echo "==> Launching $APP"
open -n "$APP"
