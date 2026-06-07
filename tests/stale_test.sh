#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLIP="$TMP/clip.mp4"
ffmpeg -y -f lavfi -i testsrc=duration=3:size=320x240:rate=4 \
       -f lavfi -i sine=frequency=440:duration=3 -shortest "$CLIP" >/dev/null 2>&1
OUT="$TMP/out"
# Run 1: produce timeline.md
uv run --script "$CLI" "$CLIP" --out "$OUT" --no-transcribe >/dev/null 2>&1
test -f "$OUT/timeline.md" || { echo "FAIL: run1 no timeline"; exit 1; }
# Run 2 into same folder with --no-timeline: stale timeline.md must be removed
uv run --script "$CLI" "$CLIP" --out "$OUT" --no-transcribe --no-timeline >/dev/null 2>&1
test ! -f "$OUT/timeline.md" || { echo "FAIL: stale timeline.md not reconciled"; exit 1; }
# Run 3 default: contact-sheet.jpg appears (and timeline returns)
uv run --script "$CLI" "$CLIP" --out "$OUT" --no-transcribe >/dev/null 2>&1
test -f "$OUT/contact-sheet.jpg" || { echo "FAIL: run3 no contact-sheet"; exit 1; }
# Run 4 with --no-contact-sheet: stale contact-sheet.jpg must be removed (second reconcile path)
uv run --script "$CLI" "$CLIP" --out "$OUT" --no-transcribe --no-contact-sheet >/dev/null 2>&1
test ! -f "$OUT/contact-sheet.jpg" || { echo "FAIL: stale contact-sheet.jpg not reconciled"; exit 1; }
echo "PASS stale"
