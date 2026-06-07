#!/usr/bin/env bash
# Regression test: write_manifest must preserve an existing manifest's `created` field.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

python3 - "$CLI" "$TMP" <<'PY'
import sys, json, types, pathlib
from pathlib import Path

cli_path = sys.argv[1]
tmp = Path(sys.argv[2])

# Load the CLI as a module without running main()
src = compile(open(cli_path).read(), cli_path, "exec")
mod = types.ModuleType("watch_video")
mod.__file__ = cli_path
exec(src, mod.__dict__)

out_dir = tmp / "testdir"
out_dir.mkdir()

# First write — establishes the manifest
mod.write_manifest(out_dir, "test-source")
mf = out_dir / ".watch-video.json"
data = json.loads(mf.read_text())
assert data["tool"] == "watch-video", "bad tool field"

# Overwrite created with an old sentinel value
OLD = "2020-01-01T00:00:00+00:00"
data["created"] = OLD
mf.write_text(json.dumps(data, indent=2) + "\n")

# Second write — must preserve the old created
mod.write_manifest(out_dir, "test-source-v2")
data2 = json.loads(mf.read_text())
assert data2["created"] == OLD, f"created was reset: {data2['created']!r} (expected {OLD!r})"
print("PASS manifest_created")
PY