#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
# Parse-level assertion runs even without tesseract — catches a forgotten flag.
uv run --script "$CLI" --help 2>/dev/null | grep -q -- "--ocr-tuned" || { echo "FAIL: --ocr-tuned not in --help"; exit 1; }
command -v tesseract >/dev/null || { echo "SKIP ocr-tuned OCR assertion (no tesseract)"; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLIP="$TMP/clip.mp4"
ffmpeg -y -f lavfi -i testsrc=duration=3:size=320x240:rate=4 \
       -f lavfi -i sine=frequency=440:duration=3 -shortest "$CLIP" >/dev/null 2>&1
OUT="$TMP/out"
uv run --script "$CLI" "$CLIP" --out "$OUT" --no-transcribe --ocr-tuned >/dev/null 2>&1
test -f "$OUT/frames/ocr-combined.md" || { echo "FAIL: ocr-combined.md missing with --ocr-tuned"; exit 1; }
echo "PASS ocr-tuned"
