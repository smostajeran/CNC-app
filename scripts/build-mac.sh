#!/usr/bin/env bash
# Build Quill on macOS (requires Xcode + XcodeGen).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SHA="$(git rev-parse --short HEAD)"
echo "==> Building Quill tip $SHA (marketing 1.3 / build 6)"

echo "==> Stamp git commit into BuildInfo.swift"
"$ROOT/scripts/stamp-build-info.sh"

restore_buildinfo() {
  git -C "$ROOT" checkout -- Quill/BuildInfo.swift 2>/dev/null || true
}
trap restore_buildinfo EXIT

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
  MARKETING_VERSION=1.3 \
  CURRENT_PROJECT_VERSION=6 \
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
PLIST="$APP/Contents/Info.plist"

# Stamp SHA into the built app's Info.plist so About/header can show the tip.
if [[ -f "$PLIST" ]]; then
  /usr/libexec/PlistBuddy -c "Set :QuillGitCommit $SHA" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :QuillGitCommit string $SHA" "$PLIST"
fi

SHORT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || echo '?')"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST" 2>/dev/null || echo '?')"
GIT="$(/usr/libexec/PlistBuddy -c 'Print :QuillGitCommit' "$PLIST" 2>/dev/null || echo '?')"

echo ""
echo "Built: $APP"
echo "Version: $SHORT ($BUILD) · $GIT"
if [[ "$SHORT" != "1.3" || "$BUILD" != "6" ]]; then
  echo "ERROR: expected marketing 1.3 / build 6, got $SHORT ($BUILD)" >&2
  exit 1
fi
if [[ "$GIT" != "$SHA" ]]; then
  echo "ERROR: expected git tip $SHA in app, got $GIT" >&2
  exit 1
fi
echo "Run:   open -n \"$APP\""
