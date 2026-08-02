#!/usr/bin/env bash
# Build TA4Host on macOS (requires Xcode + XcodeGen).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> CNCCore tests"
swift test --package-path CNCCore

echo "==> Generate Xcode project"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install with: brew install xcodegen" >&2
  exit 1
fi
xcodegen generate --spec "$ROOT/project.yml"

echo "==> Build TA4Host (Debug)"
xcodebuild \
  -project TA4Host.xcodeproj \
  -scheme TA4Host \
  -configuration Debug \
  -derivedDataPath "$ROOT/build/DerivedData" \
  build

APP="$ROOT/build/DerivedData/Build/Products/Debug/TA4Host.app"
echo ""
echo "Built: $APP"
echo "Run:   open \"$APP\""
