#!/usr/bin/env bash
# Patch AppModel.swift so noticeTitle is never cleared with nil.
# Safe to run on any tip; no-op when already fixed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/Quill/AppModel.swift"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: missing $FILE" >&2
  exit 1
fi

python3 - "$FILE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
original = text

# Clear sites: noticeTitle = nil  →  noticeTitle = ""
text, n_assign = re.subn(r"noticeTitle\s*=\s*nil\b", 'noticeTitle = ""', text)

# Optional declaration → non-optional ("" clears do not need String?)
text, n_decl = re.subn(
    r"@Published\s+var\s+noticeTitle:\s*String\?\s*=",
    '@Published var noticeTitle: String =',
    text,
)

if text != original:
    path.write_text(text, encoding="utf-8")
    print(f"Patched {path}: {n_assign} assignment(s), {n_decl} declaration(s)")
else:
    print(f"OK {path}: no noticeTitle = nil left to patch")

# Hard fail if anything remains (weird spacing / unicode nil, etc.)
leftover = [
    (i + 1, line.rstrip())
    for i, line in enumerate(text.splitlines())
    if re.search(r"noticeTitle\s*=\s*nil\b", line)
]
if leftover:
    print("ERROR: still have noticeTitle = nil:", file=sys.stderr)
    for num, line in leftover:
        print(f"  {num}: {line}", file=sys.stderr)
    sys.exit(1)

for i, line in enumerate(text.splitlines(), 1):
    if "var noticeTitle" in line:
        print(f"  declaration L{i}: {line.strip()}")
        break
PY
