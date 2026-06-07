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
