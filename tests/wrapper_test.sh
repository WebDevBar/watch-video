#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; WRAP="$HERE/scripts/watch-run.py"
command -v ffmpeg >/dev/null || { echo "SKIP wrapper: ffmpeg missing"; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLIP="$TMP/clip.mp4"
ffmpeg -y -f lavfi -i testsrc=duration=3:size=320x240:rate=4 \
       -f lavfi -i sine=frequency=440:duration=3 -shortest "$CLIP" >/dev/null 2>&1
OUT="$TMP/out"
# Wrapper must print exactly the output dir on stdout (one line), and not choke on --ephemeral.
DIR="$(python3 "$WRAP" "$CLIP" --out "$OUT" --no-transcribe --ephemeral 2>/dev/null)"
test "$DIR" = "$OUT" || { echo "FAIL: wrapper stdout '$DIR' != '$OUT'"; exit 1; }
test -f "$OUT/SUMMARY.md" || { echo "FAIL: run produced no SUMMARY"; exit 1; }
# Cleanup pass-through removes the manifested dir.
python3 "$WRAP" --clean "$OUT" >/dev/null 2>&1
test ! -d "$OUT" || { echo "FAIL: cleanup pass-through did not delete"; exit 1; }
# bare --out (no slash) must produce an ABSOLUTE path
cd "$TMP"
BARE_DIR="$(python3 "$WRAP" "$CLIP" --out bareout --no-transcribe 2>/dev/null)"
case "$BARE_DIR" in
    /*) ;;  # starts with / — absolute path, good
    *)  echo "FAIL: wrapper bare-out '$BARE_DIR' is not absolute"; exit 1 ;;
esac
# cleanup via wrapper must remove the dir
python3 "$WRAP" --clean "$BARE_DIR" >/dev/null 2>&1
test ! -d "$TMP/bareout" || { echo "FAIL: bare-out dir not cleaned"; exit 1; }
echo "PASS wrapper"
