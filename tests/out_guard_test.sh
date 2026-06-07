#!/usr/bin/env bash
# A run must refuse a non-empty --out dir it doesn't own (protects user files);
# --force overrides; a watch-video-owned dir re-runs without refusal.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
command -v ffmpeg >/dev/null || { echo "SKIP out-guard: ffmpeg missing"; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLIP="$TMP/clip.mp4"
ffmpeg -y -f lavfi -i testsrc=duration=2:size=320x240:rate=4 \
       -f lavfi -i sine=frequency=440:duration=2 -shortest "$CLIP" >/dev/null 2>&1

# Case 1: non-empty, non-watch-video --out → refused
USRDIR="$TMP/mydir"; mkdir -p "$USRDIR"; echo "keep" > "$USRDIR/important.txt"
if uv run --script "$CLI" "$CLIP" --out "$USRDIR" --no-transcribe >/dev/null 2>&1; then
  echo "FAIL: run did not refuse a non-empty unowned --out"; exit 1
fi
test -f "$USRDIR/important.txt" || { echo "FAIL: user file touched on refusal"; exit 1; }
test ! -f "$USRDIR/.watch-video.json" || { echo "FAIL: claimed dir despite refusal"; exit 1; }

# Case 2: --force overrides → run proceeds
uv run --script "$CLI" "$CLIP" --out "$USRDIR" --no-transcribe --force >/dev/null 2>&1 || { echo "FAIL: --force did not allow the run"; exit 1; }
test -f "$USRDIR/SUMMARY.md" || { echo "FAIL: --force run produced no output"; exit 1; }
test -f "$USRDIR/important.txt" || { echo "FAIL: --force run deleted the user file"; exit 1; }

# Case 3: re-run into a watch-video-owned dir → no refusal (now owned from Case 2)
uv run --script "$CLI" "$CLIP" --out "$USRDIR" --no-transcribe >/dev/null 2>&1 || { echo "FAIL: re-run into owned dir was refused"; exit 1; }

# Case 4: fresh/new --out → no refusal
uv run --script "$CLI" "$CLIP" --out "$TMP/fresh" --no-transcribe >/dev/null 2>&1 || { echo "FAIL: fresh --out refused"; exit 1; }
echo "PASS out-guard"
