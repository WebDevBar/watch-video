---
description: Watch a video/Loom and read its transcript + key frames + on-screen text.
---

Run the watch-video wrapper on the user's video and then read the result.

⚠️ Privacy: local on Claude Code/Codex. The claude.ai web surface is hosted —
**non-sensitive / public videos only**.

Steps:
1. Run: `uv run "${CLAUDE_PLUGIN_ROOT}/scripts/watch-run.py" $ARGUMENTS`
   (The wrapper enables tuned OCR by default and prints the output directory.
   `${CLAUDE_PLUGIN_ROOT}` is set by Claude Code to the installed plugin dir.)
2. Read, in order (skip any missing): `SUMMARY.md`, `timeline.md`, `transcript.md`,
   `frames/*.jpg`, `frames/ocr-combined.md` from the printed directory.
3. If the user asked for `--ephemeral`: after reading, run
   `uv run "${CLAUDE_PLUGIN_ROOT}/scripts/watch-run.py" --clean <printed-output-dir>`.
