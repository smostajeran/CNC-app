#!/usr/bin/env bash
# Force-sync the Compose branch (or patch in place), then clean-build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BRANCH="cursor/quill-precision-composer-c1ee"

echo "==> Fetch $BRANCH"
if git fetch origin "$BRANCH"; then
  if ! git diff --quiet -- Quill/Info.plist 2>/dev/null; then
    echo "==> Discarding local Quill/Info.plist edits"
    git checkout -- Quill/Info.plist || true
  fi
  echo "==> Checkout + ff-only pull"
  git checkout "$BRANCH" || true
  git pull --ff-only origin "$BRANCH" || {
    echo "==> ff-only pull failed — continuing with local fix-notice-title patch"
  }
else
  echo "==> git fetch failed — continuing with local fix-notice-title patch"
fi

# Refresh this fixer from origin when possible (so old trees get the new script).
if git show "origin/$BRANCH:scripts/fix-notice-title.sh" >/dev/null 2>&1; then
  git show "origin/$BRANCH:scripts/fix-notice-title.sh" > "$ROOT/scripts/fix-notice-title.sh"
  chmod +x "$ROOT/scripts/fix-notice-title.sh"
fi
if git show "origin/$BRANCH:scripts/build-mac.sh" >/dev/null 2>&1; then
  git show "origin/$BRANCH:scripts/build-mac.sh" > "$ROOT/scripts/build-mac.sh"
  chmod +x "$ROOT/scripts/build-mac.sh"
fi

echo "==> Tip $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "==> Patch noticeTitle before build"
"$ROOT/scripts/fix-notice-title.sh"
sed -n '200,205p;408,412p' Quill/AppModel.swift || true

echo "==> Clean build"
exec "$ROOT/scripts/clean-and-build-mac.sh"
