#!/usr/bin/env bash
# Regression test: --clean must NOT blanket-delete frames/; user files must survive.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

BASE="$TMP/watch-video-out"
DIR="$BASE/mixed"
FRAMES="$DIR/frames"
mkdir -p "$FRAMES/ocr"

# Write a valid manifest
printf '{"tool":"watch-video","version":"1.1.0","source":"x","created":"2020-01-01T00:00:00+00:00"}\n' \
    > "$DIR/.watch-video.json"

# A watch-video frame (should be deleted)
touch "$FRAMES/frame_000_0m00s.jpg"
# An ffmpeg extraction temp (should be deleted)
touch "$FRAMES/000001.jpg"
# An OCR artifact (should be deleted)
touch "$FRAMES/ocr/frame_000_0m00s.txt"
touch "$FRAMES/ocr-combined.md"

# A USER file inside frames/ (must survive)
touch "$FRAMES/user-keep.png"

# A user file in the output dir itself (must survive)
echo "my notes" > "$DIR/notes.txt"

uv run --script "$CLI" --clean mixed >/dev/null 2>&1

test -f "$FRAMES/user-keep.png"   || { echo "FAIL: user file frames/user-keep.png was deleted"; exit 1; }
test -f "$DIR/notes.txt"          || { echo "FAIL: user file notes.txt was deleted"; exit 1; }
test ! -f "$FRAMES/frame_000_0m00s.jpg" || { echo "FAIL: watch-video frame was not removed"; exit 1; }
test ! -f "$FRAMES/000001.jpg"          || { echo "FAIL: ffmpeg temp frame was not removed"; exit 1; }
test ! -f "$FRAMES/ocr-combined.md"     || { echo "FAIL: ocr-combined.md was not removed"; exit 1; }
test -d "$DIR"                          || { echo "FAIL: output dir was removed (user files inside)"; exit 1; }

echo "PASS clean_frames_safety"
