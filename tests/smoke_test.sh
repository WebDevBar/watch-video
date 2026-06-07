#!/usr/bin/env bash
# Offline-core smoke test. Hard prereqs: uv, ffmpeg, warm uv cache. tesseract optional.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"

command -v uv >/dev/null     || { echo "SKIP smoke: uv missing"; exit 0; }
command -v ffmpeg >/dev/null || { echo "SKIP smoke: ffmpeg missing"; exit 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLIP="$TMP/clip.mp4"
ffmpeg -y -f lavfi -i testsrc=duration=3:size=320x240:rate=4 \
       -f lavfi -i sine=frequency=440:duration=3 -shortest "$CLIP" >/dev/null 2>&1
OUT="$TMP/out"
uv run --script "$CLI" "$CLIP" --out "$OUT" --no-transcribe >/dev/null 2>&1

for f in SUMMARY.md timeline.md .watch-video.json; do
  test -f "$OUT/$f" || { echo "FAIL: $f missing"; exit 1; }
done
ls "$OUT"/frames/*.jpg >/dev/null 2>&1 || { echo "FAIL: no frames"; exit 1; }
if command -v tesseract >/dev/null; then
  test -f "$OUT/frames/ocr-combined.md" || { echo "FAIL: ocr-combined.md missing (tesseract present)"; exit 1; }
fi
echo "PASS smoke (offline core)"
