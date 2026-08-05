#!/usr/bin/env bash
# Stamp the current git short SHA into Quill/BuildInfo.swift before building.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/Quill/BuildInfo.swift"

if ! command -v git >/dev/null 2>&1; then
  SHA="unknown"
else
  SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi

if [[ ! -f "$FILE" ]]; then
  echo "stamp-build-info: missing $FILE" >&2
  exit 1
fi

# Replace only the gitCommit string literal.
tmp="$(mktemp)"
sed -E "s/static let gitCommit = \"[^\"]*\"/static let gitCommit = \"${SHA}\"/" "$FILE" > "$tmp"
mv "$tmp" "$FILE"
echo "stamp-build-info: Quill $SHA → BuildInfo.gitCommit"
