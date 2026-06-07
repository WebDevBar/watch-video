#!/usr/bin/env bash
# Stage the skill files (including the watch-video CLI) and zip into watch.skill.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$HERE/dist/watch.skill}"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT

# Resolve OUT to an ABSOLUTE path before we cd into $STAGE (else zip writes inside $STAGE
# and the trap deletes it — breaks relative invocations like `build-skill.sh dist/watch.skill`).
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

# Required payload — assert the CLI is present (the wrapper has nothing to run without it).
test -f "$HERE/watch-video" || { echo "ERROR: watch-video CLI not found at repo root" >&2; exit 1; }

cp "$HERE/watch-video" "$STAGE/"
cp "$HERE/SKILL.md" "$STAGE/"
mkdir -p "$STAGE/commands" "$STAGE/scripts" "$STAGE/.claude-plugin" "$STAGE/.codex-plugin"
cp "$HERE/commands/watch.md" "$STAGE/commands/"
cp "$HERE/scripts/watch-run.py" "$HERE/scripts/setup.py" "$STAGE/scripts/"
cp "$HERE/.claude-plugin/plugin.json" "$HERE/.claude-plugin/marketplace.json" "$STAGE/.claude-plugin/"
cp "$HERE/.codex-plugin/plugin.json" "$STAGE/.codex-plugin/"

mkdir -p "$(dirname "$OUT")"
( cd "$STAGE" && zip -qr "$OUT" . )
echo "built $OUT"
