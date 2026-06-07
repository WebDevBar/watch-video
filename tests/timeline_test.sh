#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLIP="$TMP/clip.mp4"
ffmpeg -y -f lavfi -i testsrc=duration=3:size=320x240:rate=4 \
       -f lavfi -i sine=frequency=440:duration=3 -shortest "$CLIP" >/dev/null 2>&1
OUT="$TMP/out"
uv run --script "$CLI" "$CLIP" --out "$OUT" --no-transcribe >/dev/null 2>&1
test -f "$OUT/timeline.md" || { echo "FAIL: timeline.md missing (default-on)"; exit 1; }
grep -q "frames/" "$OUT/timeline.md" || { echo "FAIL: timeline has no frame refs"; exit 1; }
OUT2="$TMP/out2"
uv run --script "$CLI" "$CLIP" --out "$OUT2" --no-transcribe --no-timeline >/dev/null 2>&1
test ! -f "$OUT2/timeline.md" || { echo "FAIL: timeline written despite --no-timeline"; exit 1; }
echo "PASS timeline"
