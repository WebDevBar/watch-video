#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
# On a machine that already has uv+ffmpeg, setup must succeed (exit 0) and be idempotent.
command -v uv >/dev/null && command -v ffmpeg >/dev/null || { echo "SKIP setup (uv/ffmpeg absent)"; exit 0; }
python3 "$HERE/scripts/setup.py" --check >/dev/null 2>&1 || { echo "FAIL: setup --check nonzero with deps present"; exit 1; }
echo "PASS setup"
