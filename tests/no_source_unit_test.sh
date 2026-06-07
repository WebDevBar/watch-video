#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
python3 - "$CLI" "$TMP" <<'PY'
import sys, types
from pathlib import Path
cli_path, tmp = sys.argv[1], Path(sys.argv[2])
mod = types.ModuleType("wv"); mod.__file__ = cli_path
exec(compile(open(cli_path).read(), cli_path, "exec"), mod.__dict__)
# downloaded=True → deleted
dl = tmp / "source.mp4"; dl.write_text("x")
assert mod.prune_source(dl, True) is True and not dl.exists(), "downloaded source not pruned"
# downloaded=False → kept (user's local file)
local = tmp / "mine.mp4"; local.write_text("x")
assert mod.prune_source(local, False) is False and local.exists(), "local input wrongly deleted"
print("ok")
PY
echo "PASS no-source-unit"
