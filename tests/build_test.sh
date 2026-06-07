#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
bash "$HERE/scripts/build-skill.sh" "$OUT/watch.skill" >/dev/null 2>&1
test -f "$OUT/watch.skill" || { echo "FAIL: bundle not produced"; exit 1; }
# bundle MUST contain the CLI
unzip -l "$OUT/watch.skill" | grep -q "watch-video" || { echo "FAIL: bundle missing watch-video CLI"; exit 1; }
unzip -l "$OUT/watch.skill" | grep -q "SKILL.md" || { echo "FAIL: bundle missing SKILL.md"; exit 1; }
unzip -l "$OUT/watch.skill" | grep -q ".claude-plugin/plugin.json" || { echo "FAIL: bundle missing .claude-plugin manifest"; exit 1; }
# Also exercise a RELATIVE output path exactly as the release workflow does (catches the
# cd-into-stage path bug). Run from the repo root so dist/ resolves there.
( cd "$HERE" && rm -f dist/watch.skill && bash scripts/build-skill.sh dist/watch.skill >/dev/null 2>&1 \
  && test -f dist/watch.skill ) || { echo "FAIL: relative-path build did not land at repo dist/watch.skill"; exit 1; }
rm -f "$HERE/dist/watch.skill"
echo "PASS build"
