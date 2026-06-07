#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLIP="$TMP/clip.mp4"
ffmpeg -y -f lavfi -i testsrc=duration=3:size=320x240:rate=4 \
       -f lavfi -i sine=frequency=440:duration=3 -shortest "$CLIP" >/dev/null 2>&1
OUT="$TMP/out"
# --no-source must be accepted by argparse
uv run --script "$CLI" --help 2>/dev/null | grep -q -- "--no-source" || { echo "FAIL: --no-source not in --help"; exit 1; }
# local input + --no-source: the user's local file must SURVIVE (was_downloaded=False) — the data-loss guard
uv run --script "$CLI" "$CLIP" --out "$OUT" --no-transcribe --no-source >/dev/null 2>&1
test -f "$CLIP" || { echo "FAIL: --no-source deleted the user's local input file"; exit 1; }
# This integration test asserts the SAFETY-CRITICAL half: a user's local input is never
# deleted. The downloaded-removal branch (was_downloaded=True) is asserted offline by
# tests/no_source_unit_test.sh (calls prune_source directly).
echo "PASS no-source"
