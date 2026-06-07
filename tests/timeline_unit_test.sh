#!/usr/bin/env bash
# Unit test of write_timeline's frame↔transcript↔OCR interleave — no model/network.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
python3 - "$CLI" "$TMP" <<'PY'
import sys, types
from pathlib import Path
cli_path, tmp = sys.argv[1], Path(sys.argv[2])
mod = types.ModuleType("wv"); mod.__file__ = cli_path
# Loading runs only top-level (stdlib imports); main() is gated by __name__ == "__main__".
exec(compile(open(cli_path).read(), cli_path, "exec"), mod.__dict__)
frames = tmp / "frames"; frames.mkdir(parents=True)
f0 = frames / "frame_000_0m00s.jpg"; f1 = frames / "frame_001_0m12s.jpg"
f0.write_text("x"); f1.write_text("x")
kept = [(f0, 0.0), (f1, 12.0)]
segments = [(1.0, "hello world")]        # a segment at t=1s belongs to frame 0 (0..12)
ocr_map = {f0: "Revenue $4200"}
mod.write_timeline(tmp, kept, segments, ocr_map)
out = (tmp / "timeline.md").read_text()
assert "> hello world" in out, "transcript line not interleaved at frame 0"
assert "OCR: Revenue $4200" in out, "OCR snippet missing"
assert "frame_001_0m12s.jpg" in out, "second frame missing"
print("ok")
PY
echo "PASS timeline-unit"
