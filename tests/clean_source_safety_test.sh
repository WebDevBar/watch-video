#!/usr/bin/env bash
# Regression test: --clean must NOT delete a user's pre-existing source.* file.
# Only the file recorded in downloaded_source (or none, if null) must be removed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

BASE="$TMP/watch-video-out"

# -----------------------------------------------------------------------
# Case A: user has their own source.mp4, downloaded_source is null
# → source.mp4 must SURVIVE --clean
# -----------------------------------------------------------------------
DIR_A="$BASE/userhassrc"
mkdir -p "$DIR_A"

python3 - "$DIR_A" <<'PY'
import sys, json
from pathlib import Path
d = Path(sys.argv[1])
manifest = {
    "tool": "watch-video",
    "version": "1.1.0",
    "source": "https://example.com/video",
    "downloaded_source": None,
    "created": "2020-01-01T00:00:00+00:00",
}
(d / ".watch-video.json").write_text(json.dumps(manifest, indent=2) + "\n")
PY

printf 'user content' > "$DIR_A/source.mp4"

uv run --script "$CLI" --clean userhassrc >/dev/null 2>&1

# The dir may still exist (source.mp4 keeps it non-empty) — only assert the file lives
test -f "$DIR_A/source.mp4" || { echo "FAIL Case A: user source.mp4 was deleted"; exit 1; }

# -----------------------------------------------------------------------
# Case B: watch-video downloaded source.mp4, downloaded_source is "source.mp4"
# → source.mp4 must be REMOVED by --clean, dir must be gone
# -----------------------------------------------------------------------
DIR_B="$BASE/oursrc"
mkdir -p "$DIR_B"

python3 - "$DIR_B" <<'PY'
import sys, json
from pathlib import Path
d = Path(sys.argv[1])
manifest = {
    "tool": "watch-video",
    "version": "1.1.0",
    "source": "https://example.com/video",
    "downloaded_source": "source.mp4",
    "created": "2020-01-01T00:00:00+00:00",
}
(d / ".watch-video.json").write_text(json.dumps(manifest, indent=2) + "\n")
PY

printf 'downloaded content' > "$DIR_B/source.mp4"

uv run --script "$CLI" --clean oursrc >/dev/null 2>&1

test ! -f "$DIR_B/source.mp4" || { echo "FAIL Case B: downloaded source.mp4 was not removed"; exit 1; }
test ! -d "$DIR_B"            || { echo "FAIL Case B: output dir was not removed"; exit 1; }

echo "PASS clean_source_safety"
