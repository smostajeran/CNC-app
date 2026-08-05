#!/usr/bin/env bash
# Wipe Quill build products and do a fresh macOS build + launch.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Quit any running Quill"
killall Quill 2>/dev/null || true
sleep 0.5

SHA="$(git rev-parse --short HEAD)"
BRANCH="$(git branch --show-current 2>/dev/null || echo '?')"
echo "==> Tree: $BRANCH @ $SHA"

# Prefer the PR branch that carries Compose + build fixes.
if [[ "$BRANCH" != "cursor/quill-precision-composer-c1ee" ]]; then
  echo "==> Note: not on cursor/quill-precision-composer-c1ee (on $BRANCH)."
  echo "    If Build fails on noticeTitle, run:"
  echo "      git fetch origin && git checkout cursor/quill-precision-composer-c1ee"
  echo "      git pull --ff-only origin cursor/quill-precision-composer-c1ee"
fi

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
echo "Confirm header shows: 1.3 (11) · $(git rev-parse --short HEAD)"
