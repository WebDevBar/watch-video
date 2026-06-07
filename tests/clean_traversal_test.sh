#!/usr/bin/env bash
# A crafted/corrupted manifest must NOT let --clean delete files outside the output dir.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
echo "DO NOT DELETE" > important.txt          # a file OUTSIDE the output base
mkdir -p watch-video-out/evil
# manifest with a path-traversal downloaded_source pointing at ../../important.txt
printf '{"tool":"watch-video","version":"1.1.0","source":"x","downloaded_source":"../../important.txt","created":"2020-01-01T00:00:00+00:00"}' \
  > watch-video-out/evil/.watch-video.json
uv run --script "$CLI" --clean evil >/dev/null 2>&1 || true
test -f "$TMP/important.txt" || { echo "FAIL: path traversal deleted a file outside the output dir"; exit 1; }
echo "PASS clean-traversal"
