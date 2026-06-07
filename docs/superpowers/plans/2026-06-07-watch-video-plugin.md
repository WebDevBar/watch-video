# watch-video → Claude/Codex Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package the existing `watch-video` CLI as a native skill/plugin for Claude Code, Codex, and claude.ai web (web = best-effort), without breaking the working CLI.

**Architecture:** Thin wrapper. The single-file `watch-video` uv script stays the only pipeline implementation. We add additive CLI flags (cleanup, manifest, timeline, opt-in OCR tuning, no-transcribe, no-source), then a `scripts/watch-run.py` wrapper the `/watch` command calls, plus packaging metadata (`SKILL.md`, `.claude-plugin/`, `.codex-plugin/`, `commands/`), bootstrap (`setup.py`), a bundle builder, and tests.

**Tech Stack:** Python 3.10–3.12 run via `uv run --script` (inline deps: faster-whisper, yt-dlp, Pillow, numpy, pytesseract); system `ffmpeg` + optional `tesseract`; bash for tests + bundle builder.

**Spec:** `docs/superpowers/specs/2026-06-07-watch-video-plugin-design.md` (read it first).

---

## ⛔ Editing the `watch-video` Python file — read before any task

The Claude Code **Edit tool corrupts quote characters in code files** (project rule `edit-tool-code-files.md`). When a task modifies `watch-video`, `scripts/*.py`, or any `.py`/`.sh` file, **apply the change with a Python heredoc or the Write tool — never the Edit tool.** Example pattern for inserting a function:

```bash
python3 - <<'PY'
p = 'watch-video'
s = open(p).read()
anchor = "# ---------------------------------------------------------------------------\ndef main():"
assert anchor in s, "anchor not found — re-read the file"
s = s.replace(anchor, NEW_FUNCTION + "\n\n" + anchor)
open(p, 'w').write(s)
print("ok")
PY
```

Always re-read the file after editing to confirm it still parses: `uv run --script watch-video --help` must exit 0.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `watch-video` | modify (additive) | CLI; gains manifest, `--clean*`, `--no-source`, `--no-timeline` (timeline is on by default — no `--timeline` flag needed), `--ocr-tuned`, `--no-transcribe`, stale reconciliation |
| `scripts/watch-run.py` | create | Wrapper the `/watch` command calls; resolves + runs CLI, emits output-dir line, cleanup pass-through |
| `scripts/setup.py` | create | Per-OS bootstrap: ensure uv + ffmpeg (required), tesseract (optional) |
| `scripts/build-skill.sh` | create | Stage + zip the `watch.skill` bundle (asserts CLI present) |
| `SKILL.md` | create | Skill contract across surfaces (run + read-order + privacy warning) |
| `commands/watch.md` | create | `/watch` slash command |
| `.claude-plugin/plugin.json` | create | Claude plugin manifest |
| `.claude-plugin/marketplace.json` | create | Marketplace metadata |
| `.codex-plugin/plugin.json` | create | Codex plugin manifest (format verified at impl) |
| `.github/workflows/release.yml` | create | Build bundle on tag |
| `tests/smoke_test.sh` | create | Offline-core end-to-end + clean checks |
| `CHANGELOG.md`, `LICENSE` | create | Housekeeping |
| `README.md` | modify | Mention plugin form (already has docs/ links) |

**Test approach:** the CLI is a single-file script, so tests are **bash integration tests** that invoke the CLI against a tiny synthetic clip and assert on output files. A shared helper makes the clip with ffmpeg (no network):

```bash
# make a 3s 4fps test clip with a tone — used by every test
ffmpeg -y -f lavfi -i testsrc=duration=3:size=320x240:rate=4 \
       -f lavfi -i sine=frequency=440:duration=3 -shortest \
       "$CLIP" >/dev/null 2>&1
```

Commit after every task. Conventional commit messages. No Claude attribution (project default).

---

## Task 0: Scaffold directories + warm the uv cache

The repo currently has only `watch-video`, `README.md`, `docs/`. Every later task
creates files under new directories. Git does not track empty directories, so we add
`.gitkeep` markers (committed) so the dirs exist even on a fresh checkout of any
intermediate commit. We also warm the `uv` dependency cache once, so the later
"offline-core" tests don't need network for dependency *resolution*.

- [ ] **Step 1: Make the directories with tracked placeholders**

```bash
mkdir -p tests scripts commands .claude-plugin .codex-plugin .github/workflows dist
for d in tests scripts commands .claude-plugin .codex-plugin .github/workflows; do touch "$d/.gitkeep"; done
echo "dist/" >> .gitignore   # built bundles are artifacts, not source
```

- [ ] **Step 2: Warm the uv cache (one-time network use)**

```bash
uv run --script watch-video --help >/dev/null
```
Expected: exit 0. This resolves + caches the script's inline deps (faster-whisper,
yt-dlp, Pillow, numpy, pytesseract). **After this, the offline-core tests need no
network** — they avoid only the Whisper *model* download (via `--no-transcribe`); the
*dependency* resolution is now cached. (On a fresh machine this one step needs network.)

- [ ] **Step 3: Commit**

```bash
git add .gitignore tests/.gitkeep scripts/.gitkeep commands/.gitkeep .claude-plugin/.gitkeep .codex-plugin/.gitkeep .github/workflows/.gitkeep
git commit -m "chore: scaffold plugin directories"
```

---

## Task 1: `--no-transcribe` flag + `.watch-video.json` run manifest (§5.5, §5.6)

Two tiny, offline-testable foundations, combined so each is **self-contained** (no
forward dependency): `--no-transcribe` lets later tests skip the Whisper **model**
download (so, with the uv cache warmed in Task 0, they need no network), and the
manifest is the ownership marker every later cleanup needs. We add `--no-transcribe`
first, so the manifest test can use it.

**Files:**
- Modify: `watch-video` (argparse `--no-transcribe` + minimal transcribe gate; version const + `write_manifest` + call in `main`)
- Test: `tests/no_transcribe_test.sh`, `tests/manifest_test.sh`

- [ ] **Step 1: Write the failing `--no-transcribe` test**

Create `tests/no_transcribe_test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLIP="$TMP/clip.mp4"
ffmpeg -y -f lavfi -i testsrc=duration=3:size=320x240:rate=4 \
       -f lavfi -i sine=frequency=440:duration=3 -shortest "$CLIP" >/dev/null 2>&1
OUT="$TMP/out"
uv run --script "$CLI" "$CLIP" --out "$OUT" --no-transcribe >/dev/null 2>&1
test ! -f "$OUT/transcript.md" || { echo "FAIL: transcript written despite --no-transcribe"; exit 1; }
test -d "$OUT/frames" || { echo "FAIL: frames missing"; exit 1; }
echo "PASS no-transcribe"
```

- [ ] **Step 2: Run it, expect FAIL**

Run: `bash tests/no_transcribe_test.sh`
Expected: argparse error `unrecognized arguments: --no-transcribe`.

- [ ] **Step 3: Add the `--no-transcribe` argparse flag**

In `main`, after `p.add_argument("--language")` add:

```python
    p.add_argument("--no-transcribe", action="store_true")
```

- [ ] **Step 4: Gate the transcribe call (minimal — original `transcribe` unchanged here)**

Find:

```python
    lang, n_seg = transcribe(video, out_dir, args.model, args.language)
```

Replace with:

```python
    if args.no_transcribe:
        lang, n_seg = "skipped", 0
        eprint("[transcribe] skipped (--no-transcribe)")
    else:
        lang, n_seg = transcribe(video, out_dir, args.model, args.language)
```

(The segments refactor that timeline needs comes in Task 2 — kept separate so this task stays minimal and offline-testable.)

- [ ] **Step 5: Run the `--no-transcribe` test, expect PASS**

Run: `bash tests/no_transcribe_test.sh`
Expected: `PASS no-transcribe`.

- [ ] **Step 6: Add the version constant + manifest writer**

Insert near the top of `watch-video`, after the imports block (after `from pathlib import Path`):

```python
import json
from datetime import datetime, timezone, timedelta

WATCH_VIDEO_VERSION = "1.1.0"


def write_manifest(out_dir, source):
    """Write the hidden ownership marker every cleanup operation validates."""
    manifest = {
        "tool": "watch-video",
        "version": WATCH_VIDEO_VERSION,
        "source": str(source),
        "created": datetime.now(timezone.utc).isoformat(),
    }
    (out_dir / ".watch-video.json").write_text(json.dumps(manifest, indent=2) + "\n")


def is_watch_video_dir(path):
    """True only if path holds a .watch-video.json whose SIGNATURE validates — not mere
    filename presence. The single ownership gate used by reconciliation AND cleanup."""
    mf = Path(path) / ".watch-video.json"
    if not mf.is_file():
        return False
    try:
        return json.loads(mf.read_text()).get("tool") == "watch-video"
    except Exception:
        return False
```

- [ ] **Step 7: Call it in `main` right after the output dir is created**

In `main`, find:

```python
    out_dir.mkdir(parents=True, exist_ok=True)
    frames_dir = out_dir / "frames"
    eprint(f"[watch-video] output → {out_dir}")
```

Insert immediately after that block:

```python
    write_manifest(out_dir, args.source)
```

- [ ] **Step 8: Write + run the manifest test (now uses `--no-transcribe` from Step 3 — fully offline)**

Create `tests/manifest_test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLIP="$TMP/clip.mp4"
ffmpeg -y -f lavfi -i testsrc=duration=3:size=320x240:rate=4 \
       -f lavfi -i sine=frequency=440:duration=3 -shortest "$CLIP" >/dev/null 2>&1
OUT="$TMP/out"
uv run --script "$CLI" "$CLIP" --out "$OUT" --no-transcribe >/dev/null 2>&1
test -f "$OUT/.watch-video.json" || { echo "FAIL: manifest missing"; exit 1; }
grep -q '"tool": "watch-video"' "$OUT/.watch-video.json" || { echo "FAIL: no tool signature"; exit 1; }
echo "PASS manifest"
```

Run: `bash tests/manifest_test.sh`
Expected: `PASS manifest`

- [ ] **Step 9: Verify the CLI still parses**

Run: `uv run --script watch-video --help`
Expected: exit 0, usage text showing `--no-transcribe`.

- [ ] **Step 10: Commit**

```bash
git add watch-video tests/no_transcribe_test.sh tests/manifest_test.sh
git commit -m "feat(cli): add --no-transcribe + .watch-video.json run manifest"
```

---

## Task 2: `transcribe()` returns segments (timeline prep) (§6.1)

Pure refactor: make `transcribe()` return the `(start, text)` segment list (and update
the `main` gate to expose `segments`) so Task 3's `timeline.md` can interleave them.
The `--no-transcribe` flag already exists (Task 1). Validated offline by no-regression
on the existing tests; the populated-segments path is exercised by Task 3's timeline test
and the opt-in transcription test (Task 8).

**Files:**
- Modify: `watch-video` (`transcribe` return value + the `main` transcribe gate)
- Test: re-run existing suite (no-regression)

- [ ] **Step 1: Change `transcribe` to return segments**

Replace the `transcribe` function body's tail. Find:

```python
    (out_dir / "transcript.txt").write_text("\n".join(txt) + "\n")
    return info.language, len(md)
```

Replace with:

```python
    (out_dir / "transcript.txt").write_text("\n".join(txt) + "\n")
    return info.language, segments_out
```

And change the segment loop so it accumulates `segments_out`. Find:

```python
    md, txt = [], []
    for seg in segments:
        stamp = hms(seg.start)
        line = seg.text.strip()
        md.append(f"- **[{stamp}]** {line}")
        txt.append(line)
```

Replace with:

```python
    md, txt, segments_out = [], [], []
    for seg in segments:
        stamp = hms(seg.start)
        line = seg.text.strip()
        md.append(f"- **[{stamp}]** {line}")
        txt.append(line)
        segments_out.append((seg.start, line))
```

- [ ] **Step 2: Update the `main` transcribe gate to expose `segments`**

Find the gate added in Task 1:

```python
    if args.no_transcribe:
        lang, n_seg = "skipped", 0
        eprint("[transcribe] skipped (--no-transcribe)")
    else:
        lang, n_seg = transcribe(video, out_dir, args.model, args.language)
```

Replace with:

```python
    if args.no_transcribe:
        lang, segments = "skipped", []
        eprint("[transcribe] skipped (--no-transcribe)")
    else:
        lang, segments = transcribe(video, out_dir, args.model, args.language)
    n_seg = len(segments)
```

(`segments` is now available for Task 3's timeline.)

- [ ] **Step 3: Run the existing suite — no regression**

Run: `bash tests/no_transcribe_test.sh && bash tests/manifest_test.sh`
Expected: `PASS no-transcribe` then `PASS manifest` (the refactor didn't break the skip path; `n_seg` still computed). The populated-`segments` → timeline flow is asserted **offline and deterministically by Task 3's `tests/timeline_unit_test.sh`**, which calls `write_timeline` directly with synthetic segments and checks they appear in `timeline.md` — no model needed. (Task 8's transcription test additionally checks the end-to-end path when a real-speech clip is supplied.)

- [ ] **Step 4: Verify the CLI still parses**

Run: `uv run --script watch-video --help`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add watch-video
git commit -m "refactor(cli): transcribe() returns (start,text) segments for timeline"
```

---

## Task 3: `timeline.md` generation + `--no-timeline` (§5.3, §6.1)

**Files:**
- Modify: `watch-video` (refactor `ocr_frames` to return a map, add `write_timeline`, argparse, `main`, SUMMARY)
- Test: `tests/timeline_test.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/timeline_test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLIP="$TMP/clip.mp4"
ffmpeg -y -f lavfi -i testsrc=duration=3:size=320x240:rate=4 \
       -f lavfi -i sine=frequency=440:duration=3 -shortest "$CLIP" >/dev/null 2>&1
OUT="$TMP/out"
uv run --script "$CLI" "$CLIP" --out "$OUT" --no-transcribe >/dev/null 2>&1
test -f "$OUT/timeline.md" || { echo "FAIL: timeline.md missing (default-on)"; exit 1; }
grep -q "frames/" "$OUT/timeline.md" || { echo "FAIL: timeline has no frame refs"; exit 1; }
OUT2="$TMP/out2"
uv run --script "$CLI" "$CLIP" --out "$OUT2" --no-transcribe --no-timeline >/dev/null 2>&1
test ! -f "$OUT2/timeline.md" || { echo "FAIL: timeline written despite --no-timeline"; exit 1; }
echo "PASS timeline"
```

- [ ] **Step 2: Run it, expect FAIL** (`unrecognized arguments: --no-timeline`)

- [ ] **Step 3: Make `ocr_frames` return a `{path: text}` map**

Find the end of `ocr_frames`:

```python
    (frames_dir / "ocr-combined.md").write_text("\n".join(combined) + "\n")
    return ocr_dir
```

Replace with:

```python
    (frames_dir / "ocr-combined.md").write_text("\n".join(combined) + "\n")
    return ocr_map
```

And initialize `ocr_map = {}` at the top of the function (next to `combined = []`), and inside the loop after computing `text` add `ocr_map[path] = text`.

- [ ] **Step 4: Add `write_timeline`**

Insert this function above `def main():`:

```python
def write_timeline(out_dir, kept, segments, ocr_map):
    """Chronological merge of frames + transcript + OCR. Tolerates missing inputs."""
    lines = ["# Timeline\n"]
    n = len(kept)
    for i, (path, t) in enumerate(kept):
        next_t = kept[i + 1][1] if i + 1 < n else float("inf")
        lines.append(f"## {hms(t)}")
        lines.append(f"![frame](frames/{path.name})")
        for s, said in segments:
            if t <= s < next_t:
                lines.append(f"> {said}")
        snippet = " ".join((ocr_map.get(path, "") or "").split())[:200]
        if snippet:
            lines.append(f"OCR: {snippet}")
        lines.append("")
    (out_dir / "timeline.md").write_text("\n".join(lines) + "\n")
```

- [ ] **Step 5: Add the `--no-timeline` flag + capture OCR map + call timeline in `main`**

After `p.add_argument("--no-contact-sheet", action="store_true")` add:

```python
    p.add_argument("--no-timeline", action="store_true")
```

Find the OCR block in `main`:

```python
    if do_ocr:
        eprint(f"[ocr] reading on-screen text from {len(kept)} frames…")
        ocr_frames(kept, frames_dir)
```

Replace with:

```python
    ocr_map = {}
    if do_ocr:
        eprint(f"[ocr] reading on-screen text from {len(kept)} frames…")
        ocr_map = ocr_frames(kept, frames_dir)
```

Then, after the contact-sheet block (`sheet = contact_sheet(...)`), add:

```python
    do_timeline = not args.no_timeline
    if do_timeline:
        write_timeline(out_dir, kept, segments, ocr_map)
```

- [ ] **Step 6: Add the timeline line to SUMMARY + the read-order note**

In the SUMMARY `lines = [...]` list, after the `**OCR:**` line add:

```python
        f"- **Timeline:** {'yes → timeline.md' if do_timeline else 'no'}",
```

And change the "How to read this" list to put timeline first:

```python
        "## How to read this (for an LLM/agent)",
        "0. Read this SUMMARY, then read the files it lists below (skip any not present).",
        "1. `timeline.md` interleaves each frame with what was said + on-screen text — read this first.",
        "2. `transcript.md` for the full timestamped transcript.",
        "3. Open individual `frames/*.jpg`; cross-check exact numbers against `frames/ocr-combined.md`"
        " (OCR can misread; the image is ground truth).",
```

- [ ] **Step 7: Run integration test, expect PASS**

Run: `bash tests/timeline_test.sh` → `PASS timeline`. Re-run prior tests; all PASS.

- [ ] **Step 8: Add an offline UNIT test of the interleave (loads `write_timeline` directly)**

This is what actually proves the **populated-segments → timeline** flow without a model
(the integration tests all run `--no-transcribe`). Create `tests/timeline_unit_test.sh`:

```bash
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
```

Run: `bash tests/timeline_unit_test.sh` → `PASS timeline-unit`.

- [ ] **Step 9: Commit**

```bash
git add watch-video tests/timeline_test.sh tests/timeline_unit_test.sh
git commit -m "feat(cli): timeline.md interleave (default-on) + --no-timeline"
```

---

## Task 4: Stale-artifact reconciliation (§5.7)

**Files:**
- Modify: `watch-video` (add `reconcile_stale`, call before frame extraction)
- Test: `tests/stale_test.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/stale_test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLIP="$TMP/clip.mp4"
ffmpeg -y -f lavfi -i testsrc=duration=3:size=320x240:rate=4 \
       -f lavfi -i sine=frequency=440:duration=3 -shortest "$CLIP" >/dev/null 2>&1
OUT="$TMP/out"
# Run 1: produce timeline.md
uv run --script "$CLI" "$CLIP" --out "$OUT" --no-transcribe >/dev/null 2>&1
test -f "$OUT/timeline.md" || { echo "FAIL: run1 no timeline"; exit 1; }
# Run 2 into same folder with --no-timeline: stale timeline.md must be removed
uv run --script "$CLI" "$CLIP" --out "$OUT" --no-transcribe --no-timeline >/dev/null 2>&1
test ! -f "$OUT/timeline.md" || { echo "FAIL: stale timeline.md not reconciled"; exit 1; }
# Run 3 default: contact-sheet.jpg appears (and timeline returns)
uv run --script "$CLI" "$CLIP" --out "$OUT" --no-transcribe >/dev/null 2>&1
test -f "$OUT/contact-sheet.jpg" || { echo "FAIL: run3 no contact-sheet"; exit 1; }
# Run 4 with --no-contact-sheet: stale contact-sheet.jpg must be removed (second reconcile path)
uv run --script "$CLI" "$CLIP" --out "$OUT" --no-transcribe --no-contact-sheet >/dev/null 2>&1
test ! -f "$OUT/contact-sheet.jpg" || { echo "FAIL: stale contact-sheet.jpg not reconciled"; exit 1; }
echo "PASS stale"
```

- [ ] **Step 2: Run it, expect FAIL** (`stale timeline.md not reconciled`)

- [ ] **Step 3: Add `reconcile_stale`**

Insert above `def main():`:

```python
def reconcile_stale(out_dir, frames_dir, dir_was_ours, do_transcribe, do_timeline, do_contact):
    """Remove prior watch-video artifacts this run will NOT (re)produce, so SUMMARY stays accurate.
    Acts ONLY when the folder was already a watch-video output before this run (dir_was_ours) —
    so it never touches a user's pre-existing non-watch-video folder."""
    if not dir_was_ours:
        return
    if not do_transcribe:
        (out_dir / "transcript.md").unlink(missing_ok=True)
        (out_dir / "transcript.txt").unlink(missing_ok=True)
    if not do_timeline:
        (out_dir / "timeline.md").unlink(missing_ok=True)
    if not do_contact:
        (out_dir / "contact-sheet.jpg").unlink(missing_ok=True)
    # OCR outputs are stale every re-run (frames are re-extracted) — always clear them; they are
    # regenerated this run if OCR runs. This also fixes lingering per-frame files when OCR stays on.
    (frames_dir / "ocr-combined.md").unlink(missing_ok=True)
    ocr_dir = frames_dir / "ocr"
    if ocr_dir.exists():
        for f in ocr_dir.glob("*.txt"):
            f.unlink(missing_ok=True)
    # frames are always re-extracted fresh — clear watch-video's OWN frame-name patterns only
    # (extraction temps "NNNNNN.jpg" + deduped "frame_*.jpg"), never a user's unrelated .jpg.
    if frames_dir.exists():
        for pattern in ("frame_*.jpg", "[0-9][0-9][0-9][0-9][0-9][0-9].jpg"):
            for f in frames_dir.glob(pattern):
                f.unlink(missing_ok=True)
```

- [ ] **Step 4: Capture prior ownership BEFORE the manifest is written**

The manifest is written at run start (Task 1), so by reconcile time the folder always
has a marker. To know whether it was *already* a watch-video folder before this run,
capture it just before the write. Find (added in Task 1):

```python
    write_manifest(out_dir, args.source)
```

Replace with:

```python
    dir_was_ours = is_watch_video_dir(out_dir)   # validates the manifest signature, not just presence
    write_manifest(out_dir, args.source)
```

- [ ] **Step 5: Call `reconcile_stale` in `main` before frame extraction**

The decision flags must be computed before extraction. Find:

```python
    eprint("[frames] extracting (first + scene-change + periodic)…")
    raw = extract_frames(video, frames_dir, args.periodic, args.scene_threshold)
```

Insert immediately before it:

```python
    do_transcribe = not args.no_transcribe
    do_timeline_planned = not args.no_timeline
    do_contact_planned = not args.no_contact_sheet
    frames_dir.mkdir(parents=True, exist_ok=True)
    reconcile_stale(out_dir, frames_dir, dir_was_ours, do_transcribe,
                    do_timeline_planned, do_contact_planned)
```

(`do_transcribe` here is the same flag the Task 2 transcribe gate reads.)

- [ ] **Step 6: Run test, expect PASS**

Run: `bash tests/stale_test.sh` → `PASS stale`. Re-run all prior tests.

- [ ] **Step 7: Commit**

```bash
git add watch-video tests/stale_test.sh
git commit -m "feat(cli): reconcile stale artifacts on reused output folders"
```

---

## Task 5: `--clean` cleanup mode (§5.1)

**Files:**
- Modify: `watch-video` (add `is_watch_video_dir`, `manifest_created`, `do_clean`; make `source` optional; branch in `main`)
- Test: `tests/clean_test.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/clean_test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
BASE="$TMP/watch-video-out"; mkdir -p "$BASE/demo"
printf '{"tool":"watch-video","version":"1.1.0","source":"x","created":"2020-01-01T00:00:00+00:00"}' > "$BASE/demo/.watch-video.json"
# unrelated dir with a SUMMARY.md but NO manifest must be refused
mkdir -p "$BASE/notmine"; echo "# hi" > "$BASE/notmine/SUMMARY.md"

# slug clean removes only the manifested dir
uv run --script "$CLI" --clean demo >/dev/null 2>&1
test ! -d "$BASE/demo" || { echo "FAIL: slug clean did not delete"; exit 1; }
test -d "$BASE/notmine" || { echo "FAIL: deleted dir without manifest"; exit 1; }

# clean all skips the unmanifested dir
uv run --script "$CLI" --clean all >/dev/null 2>&1
test -d "$BASE/notmine" || { echo "FAIL: --clean all deleted unmanifested dir"; exit 1; }
echo "PASS clean"
```

- [ ] **Step 2: Run it, expect FAIL** (`--clean` unrecognized, or it errors needing `source`).

- [ ] **Step 3: Add cleanup helpers**

Insert above `def main():` (`is_watch_video_dir` was already defined in Task 1 — do **not** redefine it):

```python
def manifest_created(path):
    try:
        data = json.loads((Path(path) / ".watch-video.json").read_text())
        return datetime.fromisoformat(data["created"])
    except Exception:
        return None


def _looks_like_path(arg):
    return ("/" in arg) or ("\\" in arg) or Path(arg).is_absolute()


# The exact set of files/dirs watch-video creates in an output folder.
WV_ARTIFACT_NAMES = ("SUMMARY.md", "transcript.md", "transcript.txt", "timeline.md",
                     "contact-sheet.jpg", ".watch-video.json")


def remove_wv_artifacts(d):
    """Delete ONLY watch-video's own artifacts in d, then rmdir d if it is now empty.
    Never blanket-deletes the folder: if the user pointed --out at a folder containing
    their own files, those survive and the folder is left in place."""
    d = Path(d)
    for name in WV_ARTIFACT_NAMES:
        (d / name).unlink(missing_ok=True)
    for s in d.glob("source.*"):       # the downloaded source video, if kept
        s.unlink(missing_ok=True)
    frames = d / "frames"
    if frames.exists():
        shutil.rmtree(frames, ignore_errors=True)   # frames/ is entirely watch-video-created
    try:
        d.rmdir()                      # removes the folder ONLY if nothing else remains
        return True
    except OSError:
        eprint(f"[clean] {d}: removed watch-video artifacts; folder kept (contains other files)")
        return False


def do_clean(clean_arg, older_than, base):
    targets, skipped = [], []
    if older_than is not None:
        cutoff = datetime.now(timezone.utc) - timedelta(days=older_than)
        if base.exists():
            for d in sorted(p for p in base.iterdir() if p.is_dir()):
                created = manifest_created(d)
                if is_watch_video_dir(d) and created is not None and created < cutoff:
                    targets.append(d)
                else:
                    skipped.append(d)
    elif clean_arg == "all":
        if base.exists():
            for d in sorted(p for p in base.iterdir() if p.is_dir()):
                (targets if is_watch_video_dir(d) else skipped).append(d)
    elif clean_arg and _looks_like_path(clean_arg):
        d = Path(clean_arg).expanduser()
        (targets if is_watch_video_dir(d) else skipped).append(d)
    elif clean_arg:  # bare token → slug under base
        d = base / clean_arg
        (targets if is_watch_video_dir(d) else skipped).append(d)
    for d in targets:
        removed = remove_wv_artifacts(d)
        eprint(f"[clean] {'deleted' if removed else 'cleaned (folder kept)'} {d}")
    for d in skipped:
        eprint(f"[clean] skipped (no valid watch-video manifest) {d}")
    return targets, skipped
```

(`shutil` is already imported in the CLI.)

- [ ] **Step 4: Add argparse flags + make `source` optional + branch in `main`**

Change the positional arg. Find:

```python
    p.add_argument("source", help="Loom/any URL, or a local video file")
```

Replace with:

```python
    p.add_argument("source", nargs="?", help="Loom/any URL, or a local video file")
    p.add_argument("--clean", metavar="SLUG|PATH|all",
                   help="janitorial: delete a watch-video output folder and exit")
    p.add_argument("--clean-older-than", type=int, metavar="DAYS",
                   help="janitorial: delete watch-video folders older than DAYS and exit")
```

Then, immediately after `args = p.parse_args()`, add the cleanup branch:

```python
    if args.clean is not None and args.clean_older_than is not None:
        p.error("--clean and --clean-older-than are mutually exclusive")
    if args.clean_older_than is not None and args.clean_older_than < 0:
        p.error("--clean-older-than DAYS must be >= 0")
    if args.clean is not None or args.clean_older_than is not None:
        base = Path.cwd() / "watch-video-out"
        do_clean(args.clean, args.clean_older_than, base)
        return
    if not args.source:
        p.error("source is required unless --clean/--clean-older-than is given")
```

- [ ] **Step 5: Run test, expect PASS**

Run: `bash tests/clean_test.sh` → `PASS clean`. Re-run all prior tests.

- [ ] **Step 6: Verify `--help` still works**

Run: `uv run --script watch-video --help` → exit 0.

- [ ] **Step 7: Commit**

```bash
git add watch-video tests/clean_test.sh
git commit -m "feat(cli): --clean (slug/path/all) + --clean-older-than with manifest ownership gate"
```

---

## Task 6: `--no-source` with `acquire()` provenance (§5.2)

**Files:**
- Modify: `watch-video` (`acquire` returns `(path, was_downloaded)`; argparse; prune in `main`)
- Test: `tests/no_source_test.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/no_source_test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLIP="$TMP/clip.mp4"
ffmpeg -y -f lavfi -i testsrc=duration=3:size=320x240:rate=4 \
       -f lavfi -i sine=frequency=440:duration=3 -shortest "$CLIP" >/dev/null 2>&1
OUT="$TMP/out"
# --no-source must be accepted by argparse
uv run --script "$CLI" --help 2>/dev/null | grep -q -- "--no-source" || { echo "FAIL: --no-source not in --help"; exit 1; }
# local input + --no-source: the user's local file must SURVIVE (was_downloaded=False) — the data-loss guard
uv run --script "$CLI" "$CLIP" --out "$OUT" --no-transcribe --no-source >/dev/null 2>&1
test -f "$CLIP" || { echo "FAIL: --no-source deleted the user's local input file"; exit 1; }
# This integration test asserts the SAFETY-CRITICAL half: a user's local input is never
# deleted. The downloaded-removal branch (was_downloaded=True) is asserted offline by
# tests/no_source_unit_test.sh (calls prune_source directly).
echo "PASS no-source"
```

- [ ] **Step 2: Run it, expect FAIL** (`--no-source` unrecognized).

- [ ] **Step 3: Change `acquire` to return provenance**

In `acquire`, the local-file branch. Find:

```python
    if local.exists() and local.is_file():
        eprint(f"[acquire] local file: {local}")
        return local
```

Replace with:

```python
    if local.exists() and local.is_file():
        eprint(f"[acquire] local file: {local}")
        return local, False
```

And the download return. Find:

```python
    if not mp4s:
        sys.exit("ERROR: yt-dlp produced no file (private link needs --cookies-from-browser?).")
    return mp4s[0]
```

Replace with:

```python
    if not mp4s:
        sys.exit("ERROR: yt-dlp produced no file (private link needs --cookies-from-browser?).")
    return mp4s[0], True
```

- [ ] **Step 4: Update the `acquire` call + add flag + prune**

Add the flag after the `--no-timeline` flag:

```python
    p.add_argument("--no-source", action="store_true")
```

Find:

```python
    video = acquire(args.source, out_dir, args.cookies_from_browser, args.cookies)
```

Replace with:

```python
    video, was_downloaded = acquire(args.source, out_dir, args.cookies_from_browser, args.cookies)
```

Add the pruning helper above `def main():` (a function so it can be unit-tested offline):

```python
def prune_source(video, was_downloaded):
    """Delete the source video ONLY if watch-video downloaded it. Never deletes a
    user-provided local input. Returns True if it deleted something."""
    if not was_downloaded:
        return False
    try:
        Path(video).unlink(missing_ok=True)
        eprint(f"[no-source] removed downloaded source {video}")
        return True
    except Exception as e:
        eprint(f"[no-source] could not remove source: {e}")
        return False
```

At the very end of `main`, just before the final `print(str(out_dir / "SUMMARY.md"))`, add:

```python
    if args.no_source:
        prune_source(video, was_downloaded)
```

- [ ] **Step 5: Run the integration test, expect PASS**

Run: `bash tests/no_source_test.sh` → `PASS no-source`. Re-run all prior tests.

- [ ] **Step 6: Add an offline UNIT test of BOTH provenance branches**

The integration test only proves a *local* input survives. This unit test proves the
*downloaded* branch actually deletes — offline, by calling `prune_source` directly.
Create `tests/no_source_unit_test.sh`:

```bash
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
```

Run: `bash tests/no_source_unit_test.sh` → `PASS no-source-unit`. (Also fix the misleading
note in `no_source_test.sh` from Step 1: replace the "covered by transcribe-style tests"
comment with "downloaded-removal branch is covered offline by tests/no_source_unit_test.sh".)

- [ ] **Step 7: Commit**

```bash
git add watch-video tests/no_source_test.sh tests/no_source_unit_test.sh
git commit -m "feat(cli): --no-source prunes only downloaded source (acquire returns provenance)"
```

---

## Task 7: `--ocr-tuned` opt-in OCR tuning (§5.4, §6.2)

**Files:**
- Modify: `watch-video` (`ocr_frames` gains `tuned` param + `_prep_for_ocr`; argparse; pass through)
- Test: `tests/ocr_tuned_test.sh`

- [ ] **Step 1: Write the failing test** (asserts the flag is accepted and OCR still runs)

Create `tests/ocr_tuned_test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
# Parse-level assertion runs even without tesseract — catches a forgotten flag.
uv run --script "$CLI" --help 2>/dev/null | grep -q -- "--ocr-tuned" || { echo "FAIL: --ocr-tuned not in --help"; exit 1; }
command -v tesseract >/dev/null || { echo "SKIP ocr-tuned OCR assertion (no tesseract)"; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLIP="$TMP/clip.mp4"
ffmpeg -y -f lavfi -i testsrc=duration=3:size=320x240:rate=4 \
       -f lavfi -i sine=frequency=440:duration=3 -shortest "$CLIP" >/dev/null 2>&1
OUT="$TMP/out"
uv run --script "$CLI" "$CLIP" --out "$OUT" --no-transcribe --ocr-tuned >/dev/null 2>&1
test -f "$OUT/frames/ocr-combined.md" || { echo "FAIL: ocr-combined.md missing with --ocr-tuned"; exit 1; }
echo "PASS ocr-tuned"
```

- [ ] **Step 2: Run it, expect FAIL** (`--ocr-tuned` unrecognized) or SKIP if no tesseract.

- [ ] **Step 3: Add `_prep_for_ocr` and a `tuned` param to `ocr_frames`**

Insert above `ocr_frames`:

```python
def _prep_for_ocr(img):
    """Upscale + grayscale + threshold a frame for sharper on-screen-text OCR."""
    from PIL import Image
    import numpy as np
    if img.width < 1000:
        scale = 1000 / img.width
        img = img.resize((int(img.width * scale), int(img.height * scale)), Image.LANCZOS)
    gray = np.asarray(img.convert("L"))
    thresh = gray.mean()
    bw = (gray > thresh).astype("uint8") * 255
    return Image.fromarray(bw)
```

Change `ocr_frames` signature and the per-frame OCR call. Find:

```python
def ocr_frames(frames, frames_dir):
    import pytesseract
    from PIL import Image
```

Replace with:

```python
def ocr_frames(frames, frames_dir, tuned=False):
    import pytesseract
    from PIL import Image
```

Find:

```python
        text = pytesseract.image_to_string(Image.open(path)).strip()
```

Replace with:

```python
        im = Image.open(path)
        if tuned:
            im = _prep_for_ocr(im)
            text = pytesseract.image_to_string(im, config="--psm 6").strip()
        else:
            text = pytesseract.image_to_string(im).strip()
```

- [ ] **Step 4: Add the flag + pass it through**

Add after `--no-source`:

```python
    p.add_argument("--ocr-tuned", action="store_true")
```

Find:

```python
        ocr_map = ocr_frames(kept, frames_dir)
```

Replace with:

```python
        ocr_map = ocr_frames(kept, frames_dir, tuned=args.ocr_tuned)
```

- [ ] **Step 5: Run test, expect PASS / SKIP**

Run: `bash tests/ocr_tuned_test.sh`. Re-run all prior tests.

- [ ] **Step 6: Commit**

```bash
git add watch-video tests/ocr_tuned_test.sh
git commit -m "feat(cli): --ocr-tuned opt-in OCR preprocessing for on-screen numbers"
```

---

## Task 8: Offline smoke test + transcription test (§10)

**Files:**
- Create: `tests/smoke_test.sh`

- [ ] **Step 1: Write `tests/smoke_test.sh`** (this IS the test — it asserts the assembled behavior)

```bash
#!/usr/bin/env bash
# Offline-core smoke test. Hard prereqs: uv, ffmpeg, warm uv cache. tesseract optional.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"

command -v uv >/dev/null     || { echo "SKIP smoke: uv missing"; exit 0; }
command -v ffmpeg >/dev/null || { echo "SKIP smoke: ffmpeg missing"; exit 0; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLIP="$TMP/clip.mp4"
ffmpeg -y -f lavfi -i testsrc=duration=3:size=320x240:rate=4 \
       -f lavfi -i sine=frequency=440:duration=3 -shortest "$CLIP" >/dev/null 2>&1
OUT="$TMP/out"
uv run --script "$CLI" "$CLIP" --out "$OUT" --no-transcribe >/dev/null 2>&1

for f in SUMMARY.md timeline.md .watch-video.json; do
  test -f "$OUT/$f" || { echo "FAIL: $f missing"; exit 1; }
done
ls "$OUT"/frames/*.jpg >/dev/null 2>&1 || { echo "FAIL: no frames"; exit 1; }
if command -v tesseract >/dev/null; then
  test -f "$OUT/frames/ocr-combined.md" || { echo "FAIL: ocr-combined.md missing (tesseract present)"; exit 1; }
fi
echo "PASS smoke (offline core)"
```

- [ ] **Step 2: Run it, expect PASS**

Run: `bash tests/smoke_test.sh`
Expected: `PASS smoke (offline core)`.

- [ ] **Step 3: Add an opt-in transcription test**

Create `tests/transcribe_test.sh`:

```bash
#!/usr/bin/env bash
# Opt-in: needs network/model on first run. Skips if WV_TRANSCRIBE_TEST != 1.
set -euo pipefail
[ "${WV_TRANSCRIBE_TEST:-0}" = "1" ] || { echo "SKIP transcribe (set WV_TRANSCRIBE_TEST=1)"; exit 0; }
HERE="$(cd "$(dirname "$0")/.." && pwd)"; CLI="$HERE/watch-video"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLIP="$TMP/clip.mp4"
ffmpeg -y -f lavfi -i testsrc=duration=3:size=320x240:rate=4 \
       -f lavfi -i sine=frequency=440:duration=3 -shortest "$CLIP" >/dev/null 2>&1
# Use a real-speech clip if provided (gives full transcript→timeline coverage); else the tone.
CLIP="${WV_TRANSCRIBE_CLIP:-$CLIP}"
OUT="$TMP/out"
uv run --script "$CLI" "$CLIP" --out "$OUT" --model tiny >/dev/null 2>&1
test -f "$OUT/transcript.md" || { echo "FAIL: transcript.md missing"; exit 1; }
# If segments were produced (real speech), assert they reached the timeline.
if grep -q '^- \*\*\[' "$OUT/transcript.md"; then
  grep -q '^> ' "$OUT/timeline.md" || { echo "FAIL: transcript segments did not reach timeline.md"; exit 1; }
fi
echo "PASS transcribe"
```

> **Note:** with the default tone clip Whisper emits no speech segments, so the conditional
> guard may not fire — that is expected. The **deterministic** segments→timeline guarantee
> is `tests/timeline_unit_test.sh` (Task 3), which doesn't need a model. Set
> `WV_TRANSCRIBE_CLIP=/path/to/speech.mp4` to also exercise the end-to-end transcribe path.

- [ ] **Step 4: Add a test runner**

Create `tests/run_all.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
fail=0
for t in manifest no_transcribe timeline timeline_unit stale clean no_source no_source_unit ocr_tuned smoke transcribe wrapper setup build; do
  f="$HERE/${t}_test.sh"
  [ -f "$f" ] || continue
  out="$(bash "$f" 2>&1)"; rc=$?
  echo "$out"
  [ $rc -eq 0 ] || fail=1
done
exit $fail
```

- [ ] **Step 5: Run the suite, expect all PASS/SKIP**

Run: `bash tests/run_all.sh`
Expected: every line `PASS …` or `SKIP …`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add tests/smoke_test.sh tests/transcribe_test.sh tests/run_all.sh
git commit -m "test: offline smoke suite + opt-in transcription test + runner"
```

---

## Task 9: `scripts/watch-run.py` wrapper (§9)

**Files:**
- Create: `scripts/watch-run.py`
- Test: `tests/wrapper_test.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/wrapper_test.sh`:

```bash
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
echo "PASS wrapper"
```

- [ ] **Step 2: Run it, expect FAIL** (wrapper doesn't exist).

- [ ] **Step 3: Write the wrapper**

Create `scripts/watch-run.py`:

```python
#!/usr/bin/env python3
"""Thin wrapper the /watch command calls. Resolves + runs the bundled watch-video
CLI via `uv run --script`, applies /watch defaults, and prints exactly one stdout
line: the output directory. Holds no pipeline logic. See spec §9."""
import subprocess
import sys
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent  # CLI ships at the bundle root
CLI = SKILL_DIR / "watch-video"


def run_cli(extra_args, default_ocr_tuned):
    cmd = ["uv", "run", "--script", str(CLI)]
    if default_ocr_tuned and "--no-ocr" not in extra_args and "--ocr-tuned" not in extra_args:
        cmd.append("--ocr-tuned")
    cmd += extra_args
    # CLI prints exactly one stdout line: the SUMMARY.md path. stderr passes through.
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        sys.exit(proc.returncode)
    summary_line = (proc.stdout or "").strip().splitlines()[-1] if proc.stdout.strip() else ""
    if not summary_line:
        sys.exit("watch-run: CLI produced no output path")
    return str(Path(summary_line).parent)


def run_cleanup(clean_args):
    # clean_args is already filtered to ONLY cleanup flags + their values.
    cmd = ["uv", "run", "--script", str(CLI)] + clean_args
    sys.exit(subprocess.run(cmd).returncode)


def _extract_cleanup_args(argv):
    """Keep ONLY --clean/--clean-older-than (+ their value); drop everything else
    (e.g. wrapper-only --ephemeral, processing defaults) so the janitorial CLI run is clean."""
    out, i = [], 0
    while i < len(argv):
        a = argv[i]
        if a in ("--clean", "--clean-older-than"):
            out.append(a)
            if i + 1 < len(argv):
                out.append(argv[i + 1]); i += 1
        i += 1
    return out


def main(argv):
    # Cleanup pass-through: `watch-run.py --clean <dir>` / `--clean-older-than N`
    if "--clean" in argv or "--clean-older-than" in argv:
        run_cleanup(_extract_cleanup_args(argv))
        return
    # Processing run: intercept --ephemeral (wrapper-only; not a CLI flag).
    extra = [a for a in argv if a != "--ephemeral"]
    out_dir = run_cli(extra, default_ocr_tuned=True)
    print(out_dir)  # the one and only wrapper stdout line


if __name__ == "__main__":
    main(sys.argv[1:])
```

- [ ] **Step 4: Make it executable**

Run: `chmod +x scripts/watch-run.py`

- [ ] **Step 5: Run test, expect PASS**

Run: `bash tests/wrapper_test.sh` → `PASS wrapper`.

- [ ] **Step 6: Commit**

```bash
git add scripts/watch-run.py tests/wrapper_test.sh
git commit -m "feat(wrapper): scripts/watch-run.py — run CLI, emit output dir, cleanup pass-through"
```

---

## Task 10: `scripts/setup.py` bootstrap (§8)

**Files:**
- Create: `scripts/setup.py`
- Test: `tests/setup_test.sh`

- [ ] **Step 1: Write the failing test** (idempotent + detects present tools, exits 0 when uv+ffmpeg present)

Create `tests/setup_test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
# On a machine that already has uv+ffmpeg, setup must succeed (exit 0) and be idempotent.
command -v uv >/dev/null && command -v ffmpeg >/dev/null || { echo "SKIP setup (uv/ffmpeg absent)"; exit 0; }
python3 "$HERE/scripts/setup.py" --check >/dev/null 2>&1 || { echo "FAIL: setup --check nonzero with deps present"; exit 1; }
echo "PASS setup"
```

- [ ] **Step 2: Run it, expect FAIL** (setup.py missing).

- [ ] **Step 3: Write `scripts/setup.py`**

Create `scripts/setup.py`:

```python
#!/usr/bin/env python3
"""Per-OS bootstrap for watch-video. Ensures uv + ffmpeg (required) and tesseract
(optional, warn-only). `--check` only verifies, never installs. See spec §8."""
import argparse
import platform
import shutil
import subprocess
import sys
from pathlib import Path

UV_INSTALL = "https://docs.astral.sh/uv/getting-started/installation/"


def have(b):
    return shutil.which(b) is not None


def install_uv():
    """Attempt the official uv installer (spec §8). Returns True if uv ends up present."""
    sysname = platform.system()
    if sysname == "Windows":
        cmd = ["powershell", "-ExecutionPolicy", "ByPass", "-c",
               "irm https://astral.sh/uv/install.ps1 | iex"]
    else:
        cmd = ["sh", "-c", "curl -LsSf https://astral.sh/uv/install.sh | sh"]
    print(f"[setup] installing uv: {' '.join(cmd)}")
    try:
        subprocess.run(cmd, check=False)
    except Exception as e:
        print(f"[setup] uv install attempt errored: {e}", file=sys.stderr)
    # uv installs to ~/.local/bin or ~/.cargo/bin — may not be on PATH this process; re-check both.
    if have("uv"):
        return True
    for p in (Path.home() / ".local/bin/uv", Path.home() / ".cargo/bin/uv"):
        if p.exists():
            print(f"[setup] uv installed at {p} — ensure its dir is on PATH, then re-run.",
                  file=sys.stderr)
            return False
    return False


def pkg_install(pkg):
    sysname = platform.system()
    if sysname == "Darwin" and have("brew"):
        return ["brew", "install", pkg]
    if sysname == "Linux":
        if have("dnf"):
            return ["sudo", "dnf", "install", "-y", pkg]
        if have("apt-get"):
            return ["sudo", "apt-get", "install", "-y", pkg]
    if sysname == "Windows" and have("winget"):
        return ["winget", "install", pkg]
    return None


def ensure(pkg, required, check_only):
    if have(pkg):
        print(f"[setup] {pkg}: present")
        return True
    if check_only:
        msg = f"[setup] {pkg}: MISSING"
        print(msg, file=sys.stderr)
        return not required
    cmd = pkg_install(pkg)
    if cmd is None:
        print(f"[setup] {pkg}: no supported package manager — install it manually.",
              file=sys.stderr)
        return not required
    print(f"[setup] installing {pkg}: {' '.join(cmd)}")
    ok = subprocess.run(cmd).returncode == 0 and have(pkg)
    if not ok and required:
        print(f"[setup] FAILED to install required {pkg}.", file=sys.stderr)
    return ok or (not required)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="verify only, do not install")
    args = ap.parse_args()

    ok = True
    if have("uv"):
        print("[setup] uv: present")
    elif args.check:
        print(f"[setup] uv: MISSING — install: {UV_INSTALL}", file=sys.stderr)
        ok = False
    else:
        # Attempt the official installer (spec §8). If it lands off-PATH, tell the user.
        if not install_uv():
            print(f"[setup] uv could not be made available on PATH. See: {UV_INSTALL}",
                  file=sys.stderr)
            ok = False

    ok = ensure("ffmpeg", required=True, check_only=args.check) and ok
    ensure("tesseract", required=False, check_only=args.check)  # optional: warn-only

    if not ok:
        print("[setup] one or more REQUIRED prerequisites are missing.", file=sys.stderr)
        sys.exit(1)
    print("[setup] required prerequisites satisfied (uv + ffmpeg). tesseract optional.")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Make it executable** (docs invoke it via `python3`, but keep it runnable directly too)

Run: `chmod +x scripts/setup.py`

- [ ] **Step 5: Run test, expect PASS**

Run: `bash tests/setup_test.sh` → `PASS setup`.

- [ ] **Step 6: Commit**

```bash
git add scripts/setup.py tests/setup_test.sh
git commit -m "feat(setup): per-OS bootstrap — uv+ffmpeg required, tesseract optional"
```

---

## Task 11: `SKILL.md` + `commands/watch.md` (§7, §9)

**Files:**
- Create: `SKILL.md`, `commands/watch.md`

- [ ] **Step 1: Write `SKILL.md`**

```markdown
---
name: watch
description: Watch a video (Loom / any URL / local file) — produce a timestamped transcript, deduplicated key frames, and OCR of on-screen text so the agent can read a screen-recording, including on-screen numbers. Use when the user shares a video/Loom and wants it understood.
---

# watch-video

Turn a video into agent-readable artifacts: `timeline.md` (frames interleaved with
what was said + on-screen text), `transcript.md`, `frames/*.jpg`,
`frames/ocr-combined.md`, and `SUMMARY.md`. Everything runs **locally**.

## ⚠️ Privacy (read first)
On **Claude Code** and **Codex** (local machines) transcription + OCR never leave
the machine. **The claude.ai web surface runs in a hosted sandbox — it is for
NON-SENSITIVE / PUBLIC videos only. Never send a sensitive video to the web
surface.** Output folders may contain private/financial data — never commit or
upload them.

## Dependencies
Required: `uv`, `ffmpeg`. Optional: `tesseract` (OCR). Run
`python3 "${CLAUDE_PLUGIN_ROOT}/scripts/setup.py"` once to install them (it attempts the
official `uv` installer + your OS package manager for ffmpeg; tesseract is best-effort),
or preinstall manually. If `uv`'s installer lands it outside your `PATH`, add its dir to
`PATH` and re-run.

## Invocation
Installed as a Claude Code plugin, this is invoked **namespaced** as
`/watch-video:watch`. The command resolves the wrapper via the plugin-root env var
`${CLAUDE_PLUGIN_ROOT}` (set by Claude Code to the installed plugin directory). On
Codex / manual skill installs, run the wrapper from the skill's own directory.

## How to run
The command runs the wrapper (which runs the bundled CLI and prints the output dir):

```
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/watch-run.py" <url|file> [--no-ocr] [--no-timeline] [--model small] [--ephemeral]
```

The wrapper prints exactly one line: the **output directory**.

## How to read the result (in order, skip any file not present)
1. `SUMMARY.md` — lists exactly what this run produced.
2. `timeline.md` — frames interleaved with transcript + OCR (read this first for meaning).
3. `transcript.md` — full timestamped transcript.
4. `frames/*.jpg` — open individual frames; cross-check exact numbers against
   `frames/ocr-combined.md` (OCR can misread; the image is ground truth).

## Ephemeral mode (two steps — delete after reading)
`--ephemeral` does NOT auto-delete (the CLI exits before you read). Do this:
1. Run `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/watch-run.py" <src> --ephemeral` → note the printed output dir.
2. After you have read the artifacts, run
   `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/watch-run.py" --clean <output-dir>` to delete them.

## Cleanup
- `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/watch-run.py" --clean <slug|path>` — delete one run's folder.
- `... --clean all` — delete all watch-video folders under `./watch-video-out/`.
- `... --clean-older-than 7` — delete folders older than 7 days.
Cleanup only deletes folders carrying a valid `.watch-video.json` marker.
```

- [ ] **Step 2: Write `commands/watch.md`**

```markdown
---
description: Watch a video/Loom and read its transcript + key frames + on-screen text.
---

Run the watch-video wrapper on the user's video and then read the result.

⚠️ Privacy: local on Claude Code/Codex. The claude.ai web surface is hosted —
**non-sensitive / public videos only**.

Steps:
1. Run: `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/watch-run.py" $ARGUMENTS`
   (The wrapper enables tuned OCR by default and prints the output directory.
   `${CLAUDE_PLUGIN_ROOT}` is set by Claude Code to the installed plugin dir.)
2. Read, in order (skip any missing): `SUMMARY.md`, `timeline.md`, `transcript.md`,
   `frames/*.jpg`, `frames/ocr-combined.md` from the printed directory.
3. If the user asked for `--ephemeral`: after reading, run
   `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/watch-run.py" --clean <printed-output-dir>`.
```

- [ ] **Step 3: Sanity check the front matter parses** (no test framework; just confirm files exist and are valid markdown)

Run: `head -5 SKILL.md commands/watch.md`
Expected: YAML front matter visible on both.

- [ ] **Step 4: Commit**

```bash
git add SKILL.md commands/watch.md
git commit -m "feat(skill): SKILL.md + /watch command (run + read-order + privacy + ephemeral)"
```

---

## Task 12: Plugin manifests (§9)

**Files:**
- Create: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.codex-plugin/plugin.json`

> **Verify formats at impl:** confirm the current Claude plugin + marketplace schema and the Codex plugin schema against live docs / the reference repos (`mathiaschu/watch`, `bradautomates/claude-video`) before finalizing. The values below are the intended shape.

- [ ] **Step 1: Write `.claude-plugin/plugin.json`**

```json
{
  "name": "watch-video",
  "version": "1.1.0",
  "description": "Watch a video/Loom into a transcript + key frames + OCR for an agent. Local-first.",
  "author": {"name": "webdevbar"},
  "commands": ["./commands/watch.md"]
}
```

Notes (per current Claude plugin docs — confirm in Step 5): `author` is an **object**;
custom component paths are **relative, `./`-prefixed**. `skills` is omitted — a root
`SKILL.md` is **auto-discovered**, so listing it (and as a bare filename) is wrong.

- [ ] **Step 2: Write `.claude-plugin/marketplace.json`**

```json
{
  "name": "watch-video",
  "owner": {"name": "webdevbar"},
  "plugins": [
    {
      "name": "watch-video",
      "source": "./",
      "description": "Watch a video/Loom into transcript + frames + OCR (local-first)."
    }
  ]
}
```

Notes: `owner` is an **object**; a root-of-repo plugin `source` is `"./"`. The plugin
`name` is `watch-video` (matches `plugin.json`), so the command is invoked **namespaced**
as `/watch-video:watch` once installed (see Step 5 / Task 11).

- [ ] **Step 3: Write `.codex-plugin/plugin.json`**

```json
{
  "name": "watch-video",
  "version": "1.1.0",
  "description": "Watch a video/Loom into a transcript + key frames + OCR for an agent. Local-first.",
  "command": "commands/watch.md",
  "skill": "SKILL.md"
}
```

- [ ] **Step 4: Validate JSON syntax**

Run: `for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json .codex-plugin/plugin.json; do python3 -c "import json,sys; json.load(open('$f'))" && echo "ok $f"; done`
Expected: `ok` for all three.

- [ ] **Step 5: Verify SCHEMA compatibility (manual — JSON-valid ≠ schema-valid)**

JSON parsing does not prove the manifests are usable by the target plugin systems. Before committing, confirm each manifest's required keys/shape against an authoritative source:
- **Claude plugin + marketplace:** compare `plugin.json` / `marketplace.json` field-for-field against a current reference repo (`mathiaschu/watch`, `bradautomates/claude-video`) and the live `/plugin` docs. Adjust keys to match.
- **Codex plugin:** the schema is not assumed — confirm `.codex-plugin/plugin.json` against current Codex docs / the reference repo's `.codex-plugin/` layout, then reconcile.
- **Smoke-install (if feasible):** `claude` → `/plugin marketplace add <local-path>` and confirm the `watch-video` plugin installs and the namespaced command `/watch-video:watch` appears. Record the result in the commit message.
Do not proceed to Task 13 until the manifests match a real schema, not just valid JSON.

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json .codex-plugin/plugin.json
git commit -m "feat(packaging): Claude + Codex plugin/marketplace manifests"
```

---

## Task 13: `scripts/build-skill.sh` bundle builder (§9)

**Files:**
- Create: `scripts/build-skill.sh`
- Test: `tests/build_test.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/build_test.sh`:

```bash
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
```

> **Depends on Task 12** — the manifests must exist before this bundles them. Run Task 13 after Task 12.

- [ ] **Step 2: Run it, expect FAIL** (builder missing).

- [ ] **Step 3: Write `scripts/build-skill.sh`**

```bash
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
```

- [ ] **Step 4: Make executable + run test**

Run: `chmod +x scripts/build-skill.sh && bash tests/build_test.sh`
Expected: `PASS build`.

- [ ] **Step 5: Commit**

```bash
git add scripts/build-skill.sh tests/build_test.sh
git commit -m "feat(packaging): build-skill.sh bundles watch.skill (asserts CLI present)"
```

---

## Task 14: Release workflow + housekeeping (§9)

**Files:**
- Create: `.github/workflows/release.yml`, `CHANGELOG.md`, `LICENSE`
- Modify: `README.md`

- [ ] **Step 1: Write `.github/workflows/release.yml`**

```yaml
name: release
on:
  push:
    tags: ["v*"]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build skill bundle
        run: bash scripts/build-skill.sh dist/watch.skill
      - name: Attach bundle to release
        uses: softprops/action-gh-release@v2
        with:
          files: dist/watch.skill
```

- [ ] **Step 2: Write `CHANGELOG.md`**

```markdown
# Changelog

## 1.1.0 — 2026-06-07
- Packaged as a Claude Code / Codex / claude.ai-web skill (thin wrapper around the CLI).
- CLI additions (non-destructive): `.watch-video.json` manifest, `--clean`/`--clean-older-than`,
  `--no-source`, `timeline.md` on by default + `--no-timeline`, `--ocr-tuned`, `--no-transcribe`,
  stale-artifact reconciliation.
- New: `scripts/watch-run.py` wrapper, `scripts/setup.py` bootstrap, `scripts/build-skill.sh`,
  `SKILL.md`, `commands/watch.md`, plugin manifests, smoke tests.

## 1.0.0
- Initial single-file CLI: local Loom/URL/file → transcript + deduped frames + OCR.
```

- [ ] **Step 3: Write `LICENSE`** (MIT, owner: webdevbar)

```
MIT License

Copyright (c) 2026 webdevbar

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 4: Update `README.md`** — under the existing "Status / future" section, add a line pointing at the plugin form. Apply with Python (not Edit tool):

```bash
python3 - <<'PY'
p = 'README.md'
s = open(p).read()
anchor = "## Docs"
add = ("## Plugin form\n\n"
       "Installable as a Claude Code / Codex skill. Install deps with "
       "`python3 scripts/setup.py`, then invoke the namespaced `/watch-video:watch` command "
       "(wraps `scripts/watch-run.py`). claude.ai web: non-sensitive/public videos only "
       "(hosted sandbox). See `SKILL.md`.\n\n")
assert anchor in s, "anchor '## Docs' not found in README"
s = s.replace(anchor, add + anchor, 1)
open(p, 'w').write(s)
print("ok")
PY
```

- [ ] **Step 5: Validate YAML + run full suite once more**

Run (validates YAML, failing on *invalid* YAML but skipping cleanly if PyYAML is absent, then runs the suite):

```bash
python3 - <<'PY' && bash tests/run_all.sh
try:
    import yaml
except ImportError:
    print("(pyyaml absent — skip yaml check)"); raise SystemExit(0)
yaml.safe_load(open(".github/workflows/release.yml"))  # raises SystemExit≠0 on invalid YAML
print("yaml ok")
PY
```
Expected: `yaml ok` (or the skip line) then every test `PASS`/`SKIP`, exit 0. The `&&` means invalid YAML (Python exits non-zero) **short-circuits and fails the step** — `tests/run_all.sh` never runs to mask it.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/release.yml CHANGELOG.md LICENSE README.md
git commit -m "chore(packaging): release workflow, changelog, license, README plugin note"
```

---

## Task 15: Final verification pass

**Files:** none (verification only)

- [ ] **Step 1: CLI still parses + help lists all new flags**

Run: `uv run --script watch-video --help`
Expected: exit 0; shows `--clean`, `--clean-older-than`, `--no-source`, `--no-timeline`, `--ocr-tuned`, `--no-transcribe`.

- [ ] **Step 2: Full test suite green**

Run: `bash tests/run_all.sh`
Expected: every line `PASS …`/`SKIP …`, exit 0.

- [ ] **Step 3: End-to-end via the wrapper on the real machine**

Run:
```bash
TMP=$(mktemp -d); ffmpeg -y -f lavfi -i testsrc=duration=4:size=640x360:rate=4 \
  -f lavfi -i sine=frequency=440:duration=4 -shortest "$TMP/c.mp4" >/dev/null 2>&1
python3 scripts/watch-run.py "$TMP/c.mp4" --out "$TMP/o" --no-transcribe
ls "$TMP/o"
python3 scripts/watch-run.py --clean "$TMP/o"; test ! -d "$TMP/o" && echo "cleaned"
```
Expected: prints `$TMP/o`; lists SUMMARY.md/timeline.md/frames/.watch-video.json; then `cleaned`.

- [ ] **Step 4: Confirm no Edit-tool quote corruption** (the CLI imports clean)

Run: `uv run --script watch-video --clean nonexistent-slug` (should print a skip line, exit 0, no traceback).

- [ ] **Step 5: Final commit if anything was touched** (otherwise nothing to do)

```bash
git status --short
```
