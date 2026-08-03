#!/usr/bin/env bash
# Build Quill on macOS (requires Xcode + XcodeGen).
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

LOG="$ROOT/build/xcodebuild.log"
mkdir -p "$ROOT/build"

echo "==> Build Quill (Debug, ad-hoc sign)"
set +e
xcodebuild \
  -project Quill.xcodeproj \
  -scheme Quill \
  -configuration Debug \
  -derivedDataPath "$ROOT/build/DerivedData" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  ENABLE_HARDENED_RUNTIME=NO \
  build 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
set -e

if [[ "$STATUS" -ne 0 ]]; then
  echo ""
  echo "==> Build failed. Last errors:"
  grep -E "error:|fatal error|BUILD FAILED" "$LOG" | tail -40 || true
  echo ""
  echo "Full log: $LOG"
  exit "$STATUS"
fi

APP="$ROOT/build/DerivedData/Build/Products/Debug/Quill.app"
echo ""
echo "Built: $APP"
echo "Run:   open \"$APP\""
