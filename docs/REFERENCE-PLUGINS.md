# Reference plugins — packaging knowledge to draw from

When we package watch-video as a native Claude Code skill/plugin (see
[PACKAGING.md](PACKAGING.md)), these two existing plugins are our **templates
for the releasable form**. They have already solved skill/plugin packaging,
the marketplace `.skill` layout, and the agent-invocation flow. We adopt their
*packaging*, not their *pipeline* — our content edge (local OCR, dedupe,
faster-whisper, Loom-native) is described in [WHY.md](WHY.md).

> **Lineage:** `mathiaschu/watch` is a **fork of `bradautomates/claude-video`**,
> with the cloud Whisper API swapped for local transcription. So they share the
> same packaging skeleton — `watch` is the closer reference for us because it's
> already local-first.

## 1. `mathiaschu/watch` — closest reference (local-first)

- **Repo:** https://github.com/mathiaschu/watch
- **What it does:** `/watch` command — yt-dlp downloads, ffmpeg extracts frames,
  captions-or-local-Whisper transcribes, frames + timestamped transcript go to
  Claude. Temp files cleaned up after.
- **Transcription:** fully local — `mlx-whisper` (Apple Silicon GPU/Neural
  Engine) preferred, `openai-whisper` (CPU) fallback. No API keys, no cloud.
- **Privacy:** "Audio never leaves your machine."
- **Auth sources:** `--cookies-from-browser chrome` / `--cookies FILE` for
  login-gated platforms (Instagram, X, private videos).
- **OCR:** none. **Frame dedupe:** none.
- **Packaging files (the parts we mine):**
  ```
  .claude-plugin/         plugin.json + marketplace.json (marketplace metadata)
  SKILL.md                the skill contract loaded across surfaces
  commands/               the /watch slash command
  hooks/
  scripts/setup.py        zero-config dependency install
  .github/workflows/      CI / release automation
  CHANGELOG.md LICENSE README.md
  ```
- **Install paths:**
  ```
  /plugin marketplace add mathiaschu/claude-video
  /plugin install watch@claude-video
  ```

## 2. `bradautomates/claude-video` — the original (cloud transcription)

- **Repo:** https://github.com/bradautomates/claude-video
- **What it does:** same 7-step pipeline (download → frames → transcript →
  Claude → cleanup). "Give Claude the ability to watch any video."
- **Transcription:** native captions first (free), then **cloud** Whisper —
  **Groq** `whisper-large-v3` (preferred) or **OpenAI** `whisper-1` (fallback).
  Requires API keys. ← the privacy blocker for us.
- **Auth sources:** explicitly **not** private/authenticated platforms.
- **OCR:** none. **Frame dedupe:** none.
- **Extra packaging worth noting:**
  ```
  .claude-plugin/plugin.json + marketplace.json
  .codex-plugin/                  Codex-specific packaging
  scripts/build-skill.sh          builds the distributable watch.skill bundle
  SKILL.md
  ```
- **Install paths:** Claude Code (`/plugin marketplace add ...`), claude.ai web
  (upload `watch.skill`), or manual clone into `~/.claude/skills/watch` /
  `~/.codex/skills/watch`.

## Packaging patterns common to both (adopt these)

- **`SKILL.md`** is the single skill contract loaded across Claude Code,
  claude.ai web, and Codex — one file, multiple surfaces.
- **`.claude-plugin/{plugin.json, marketplace.json}`** for marketplace install.
- **`.codex-plugin/`** + **`scripts/build-skill.sh`** to emit a portable
  `.skill` bundle (so it works on claude.ai web upload and Codex too).
- **`commands/`** exposes the user-facing **`/watch`** slash command.
- **`scripts/setup.py`** does **zero-config dependency install** (brew on macOS,
  apt/dnf on Linux, winget/pip on Windows) — the model to follow for our
  ffmpeg/tesseract/uv bootstrap.
- **Adaptive frame budgeting:** both cap frames to manage token cost
  (~30 frames ≤30s, ~60 for 1–3 min, sparse beyond; 2 fps floor, 100 frame
  ceiling) and support `--start`/`--end` windowing. Our dedupe is a different
  lever toward the same goal — worth reconciling the two when we spec.

## What we deliberately do NOT copy

- Cloud transcription (privacy).
- Ephemeral-only output (we keep a persistent, re-readable output folder +
  `SUMMARY.md`).
- The no-OCR, no-dedupe pipeline (those are our additions).
