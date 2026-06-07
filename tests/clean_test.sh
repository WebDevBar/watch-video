#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
BASE="$TMP/watch-video-out"; mkdir -p "$BASE/demo"
printf '{"tool":"watch-video","version":"1.1.0","source":"x","created":"2020-01-01T00:00:00+00:00"}' > "$BASE/demo/.watch-video.json"
# unrelated dir with a SUMMARY.md but NO manifest must be refused
mkdir -p "$BASE/notmine"; echo "# hi" > "$BASE/notmine/SUMMARY.md"

# slug clean removes only the manifested dir
uv run --script "$CLI" --clean demo >/dev/null 2>&1
test ! -d "$BASE/demo" || { echo "FAIL: slug clean did not delete"; exit 1; }
test -d "$BASE/notmine" || { echo "FAIL: deleted dir without manifest"; exit 1; }

# clean all skips the unmanifested dir
uv run --script "$CLI" --clean all >/dev/null 2>&1
test -d "$BASE/notmine" || { echo "FAIL: --clean all deleted unmanifested dir"; exit 1; }
echo "PASS clean"
