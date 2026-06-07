#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
fail=0
for t in manifest no_transcribe timeline timeline_unit stale clean clean_frames_safety clean_source_safety clean_traversal out_guard no_source no_source_unit ocr_tuned smoke transcribe wrapper setup build manifest_created; do
  f="$HERE/${t}_test.sh"
  [ -f "$f" ] || continue
  out="$(bash "$f" 2>&1)"; rc=$?
  echo "$out"
  [ $rc -eq 0 ] || fail=1
done
exit $fail
