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

## Transcription backend — caveats & upgrade paths

v1 uses **`faster-whisper` on CPU (int8)**. Fine for occasional few-minute videos;
a multi-minute Loom transcribes in well under real-time on a modern CPU.

- **CPU (default):** zero GPU setup, fully portable. Slower on long videos — bump to a
  smaller `--model` (`base`/`tiny`) if needed, or accept the wait.
- **NVIDIA / CUDA:** `faster-whisper` supports CUDA out of the box. With an NVIDIA GPU,
  set `device="cuda"`, `compute_type="float16"` in `transcribe()` (or expose a
  `--device` flag) for a ~4× speedup. Needs CUDA + cuDNN libs.
- **AMD (ROCm) / Apple Silicon / cross-vendor GPU:** `faster-whisper` (CTranslate2) has
  **no ROCm or Metal** path — it runs CPU-only on AMD/Mac. For GPU there, swap the
  backend to **`whisper.cpp` with Vulkan** (works on AMD RDNA, Intel, NVIDIA) or Metal
  (Apple). This is why the backend is kept isolated in `transcribe()` — it's a
  drop-in swap, not a rewrite. (This machine is AMD RDNA4 → CPU now, whisper.cpp+Vulkan
  is the future GPU path.)

## Privacy

The recordings may contain private/financial client data. Transcription + OCR are
**local by design**. The output folder therefore contains sensitive data — it's
`.gitignore`d here; **never commit an output folder**. For private Loom links, cookies
are read locally via `--cookies-from-browser`; they're sensitive — never copy them into
output/transcripts.

## Status / future

**Not yet published** — internal tool. When we package it for release, use
[`mathiaschu/watch`](https://github.com/mathiaschu/watch) as the **template** for the
releasable form: it already solved native **Claude Code skill/plugin packaging** (so the
agent invokes it and gets frames+transcript directly in-context, instead of running the
CLI and reading the output folder) and the marketplace `.skill` layout. Fold that
packaging in, keep our OCR + faster-whisper + dedupe edge. (Decision to build vs adopt
was peer-reviewed with Codex — no popular maintained tool fits the local + Loom-native +
financial-OCR requirements; the 1763★ option is cloud-transcription.)
