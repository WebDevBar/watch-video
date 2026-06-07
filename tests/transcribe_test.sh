#!/usr/bin/env bash
# Opt-in: needs network/model on first run. Skips if WV_TRANSCRIBE_TEST != 1.
set -euo pipefail
[ "${WV_TRANSCRIBE_TEST:-0}" = "1" ] || { echo "SKIP transcribe (set WV_TRANSCRIBE_TEST=1)"; exit 0; }
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLIP="$TMP/clip.mp4"
ffmpeg -y -f lavfi -i testsrc=duration=3:size=320x240:rate=4 \
       -f lavfi -i sine=frequency=440:duration=3 -shortest "$CLIP" >/dev/null 2>&1
# Use a real-speech clip if provided (gives full transcript->timeline coverage); else the tone.
CLIP="${WV_TRANSCRIBE_CLIP:-$CLIP}"
OUT="$TMP/out"
uv run --script "$CLI" "$CLIP" --out "$OUT" --model tiny >/dev/null 2>&1
test -f "$OUT/transcript.md" || { echo "FAIL: transcript.md missing"; exit 1; }
# If segments were produced (real speech), assert they reached the timeline.
if grep -q '^- \*\*\[' "$OUT/transcript.md"; then
  grep -q '^> ' "$OUT/timeline.md" || { echo "FAIL: transcript segments did not reach timeline.md"; exit 1; }
fi
echo "PASS transcribe"
