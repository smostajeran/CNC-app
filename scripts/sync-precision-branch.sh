#!/usr/bin/env bash
# Force-sync the Compose / serpentine fix branch, then clean-build.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BRANCH="cursor/quill-precision-composer-c1ee"

echo "==> Fetch $BRANCH"
git fetch origin "$BRANCH"

# Local Info.plist edits from Xcode often block pull — discard those only.
if ! git diff --quiet -- Quill/Info.plist 2>/dev/null; then
  echo "==> Discarding local Quill/Info.plist edits (Xcode often dirties this)"
  git checkout -- Quill/Info.plist
fi

echo "==> Checkout + ff-only pull"
git checkout "$BRANCH"
git pull --ff-only origin "$BRANCH"

echo "==> Tip $(git rev-parse --short HEAD)"
grep -n 'noticeTitle' Quill/AppModel.swift | head -5
echo "==> Clean build"
exec "$ROOT/scripts/clean-and-build-mac.sh"
