# watch-video

Turn a video (**Loom** / any URL / local file) into something an LLM coding agent
can actually read: a **timestamped transcript** + a **deduplicated set of key frames**
+ optional **OCR of on-screen text**. Built so a CLI agent (Claude Code, etc.) can
"watch" a client's screen-recording and decipher sparse/non-technical instructions —
including financial figures shown on screen.

**Everything runs locally.** `yt-dlp` + `ffmpeg` + `faster-whisper` + `tesseract`.
No video or audio is sent to any cloud service — important when a recording contains
private or financial data. (The only thing that leaves your machine is whatever you
or your agent later choose to read out of the output folder.)

## Usage

```bash
watch-video <loom-url | any-url | local-file.mp4> [options]
# private/team Loom:
watch-video https://www.loom.com/share/XXXX --cookies-from-browser firefox
```

Output folder (default `./watch-video-out/<slug>/`):
`SUMMARY.md` (read first) · `transcript.md` / `.txt` · `frames/*.jpg` ·
`frames/ocr-combined.md` · `contact-sheet.jpg`.

Key options: `--out`, `--model tiny|base|small|medium|large-v3` (default `small`),
`--periodic SECONDS` (4), `--scene-threshold` (0.08), `--max-frames` (200),
`--dedupe-distance` (6), `--no-ocr`, `--no-contact-sheet`, `--language`. See `--help`.

## Install / dependencies

- **uv** (runs the single-file script with inline deps; first run builds the env).
  The script's shebang is `uv run --script`, so `chmod +x watch-video` then run it.
- **ffmpeg** (frame extraction), **tesseract** (OCR, optional) — system binaries.
- `yt-dlp`, `faster-whisper`, `Pillow`, `numpy`, `pytesseract` — pulled by uv.
- Pinned to **Python 3.10–3.12** (faster-whisper/ctranslate2 wheels; 3.13+ may lack
  wheels). `uv python install 3.12` if uv can't find one.

## Transcription backend

v1 uses **`faster-whisper` on CPU (int8)** — zero GPU setup, fully portable. The
backend is isolated in one `transcribe()` function so it's a drop-in swap to
CUDA (NVIDIA, ~4×) or **whisper.cpp + Vulkan** (AMD/Intel GPU). Full caveats and
upgrade paths: [`docs/TRANSCRIPTION-BACKENDS.md`](docs/TRANSCRIPTION-BACKENDS.md).

## Privacy

The recordings may contain private/financial client data. Transcription + OCR are
**local by design**. The output folder therefore contains sensitive data — it's
`.gitignore`d here; **never commit an output folder**. For private Loom links, cookies
are read locally via `--cookies-from-browser`; they're sensitive — never copy them into
output/transcripts.

## Status / future

**Not yet published** — internal tool. The plan is to package it as a native
Claude Code skill/plugin so the agent invokes it and gets frames + transcript
directly in-context, reusing the packaging two existing plugins already solved
while keeping our OCR + faster-whisper + dedupe edge.

## Docs

- [`docs/WHY.md`](docs/WHY.md) — why this exists (privacy, Loom-native,
  financial-OCR) and what it adds over similar plugins.
- [`docs/REFERENCE-PLUGINS.md`](docs/REFERENCE-PLUGINS.md) — similar plugins to
  draw packaging knowledge from (`mathiaschu/watch`, `bradautomates/claude-video`).
- [`docs/PACKAGING.md`](docs/PACKAGING.md) — plan/target layout for the
  skill/plugin form (open questions land in the upcoming spec).
- [`docs/TRANSCRIPTION-BACKENDS.md`](docs/TRANSCRIPTION-BACKENDS.md) — CPU/CUDA/
  Vulkan caveats and upgrade paths.
