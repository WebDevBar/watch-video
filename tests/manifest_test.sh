#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLIP="$TMP/clip.mp4"
ffmpeg -y -f lavfi -i testsrc=duration=3:size=320x240:rate=4 \
       -f lavfi -i sine=frequency=440:duration=3 -shortest "$CLIP" >/dev/null 2>&1
OUT="$TMP/out"
uv run --script "$CLI" "$CLIP" --out "$OUT" --no-transcribe >/dev/null 2>&1
test -f "$OUT/.watch-video.json" || { echo "FAIL: manifest missing"; exit 1; }
grep -q '"tool": "watch-video"' "$OUT/.watch-video.json" || { echo "FAIL: no tool signature"; exit 1; }
echo "PASS manifest"
