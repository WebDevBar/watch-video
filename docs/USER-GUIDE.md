# watch-video — User Guide

A step-by-step guide to installing and using `watch-video`, both as an agent plugin and
as a command-line tool. For the project overview see the [README](../README.md).

> **Platforms.** Linux and macOS are supported. Windows should work (the plugin runs the
> tool via `uv run`, no `python3`-on-PATH assumption) but isn't maintainer-tested — see
> the README's *Platform support* table. On Windows, the CLI examples below that start
> with `./watch-video …` should be run as `uv run --script watch-video …`, and use
> `python`/`py` if `python3` isn't found. The Bash test/build scripts need Git Bash or WSL.

## 1. Install the dependencies

`watch-video` needs **`uv`** and **`ffmpeg`** (required) and **`tesseract`** (optional,
for OCR). The quickest path:

```bash
python3 scripts/setup.py
```

This attempts the official `uv` installer, installs `ffmpeg` via your OS package manager
(`brew` / `apt` / `dnf` / `winget`), and best-effort installs `tesseract`. To only check
what's present without installing anything:

```bash
python3 scripts/setup.py --check
```

If `uv`'s installer puts it somewhere not yet on your `PATH`, add that directory to
`PATH` and re-run. To install manually, see the table in the README.

## 2. First run

### Through an agent (Claude Code)

After installing the plugin (README → Install → A), just point the command at a video:

```
/watch-video:watch https://www.loom.com/share/abc123
```

The agent runs the tool, then reads `SUMMARY.md`, `timeline.md`, the frames, and the OCR
to understand the recording. Ask your question in the same breath:

```
/watch-video:watch ./bug-report.mp4   then tell me which form field is misbehaving
```

### As a CLI

```bash
./watch-video ./demo.mp4
```

When it finishes it prints the path to `SUMMARY.md`. Open that first — it lists exactly
what the run produced and the order to read it in.

## 3. Reading the output

A run writes everything into `./watch-video-out/<slug>/` (or your `--out`). Read in this
order, skipping anything a run didn't produce:

1. **`SUMMARY.md`** — metadata + artifact list + read order.
2. **`timeline.md`** — the most useful view: each frame next to what was said and what
   was on screen at that timestamp.
3. **`transcript.md`** — the full timestamped transcript.
4. **`frames/*.jpg`** — open individual frames. For an exact on-screen number, read
   `frames/ocr-combined.md` *and* look at the frame image — OCR can misread, so the
   image is the ground truth.

## 4. Common scenarios

### A private or team Loom

Loom share links that require login are fetched using your **local browser cookies** —
nothing is uploaded:

```bash
./watch-video https://www.loom.com/share/XXXX --cookies-from-browser firefox
```

Supported browsers match `yt-dlp`'s (`firefox`, `chrome`, `chromium`, `edge`, …). Or
export a Netscape `cookies.txt` and pass `--cookies cookies.txt`.

### A long video, or one where you only care about a busy section

- Increase sampling density with `--periodic 2` (a frame every 2s) for a fast-moving UI.
- Raise or lower `--max-frames` (default 200) to cap how many frames are kept.
- `--dedupe-distance` controls how aggressively near-identical frames are dropped
  (higher = more aggressive de-duplication).

### Reading on-screen numbers accurately (dashboards, invoices)

```bash
./watch-video ./stripe-dashboard.mp4 --ocr-tuned
```

`--ocr-tuned` upscales each frame, converts to high-contrast black/white, and uses an OCR
mode suited to dense UI text. (The `/watch-video:watch` agent command enables this by
default.) Always confirm a critical figure against the frame image.

### Skipping parts of the pipeline

- `--no-transcribe` — no audio transcription (fast; no model download). `timeline.md`
  then shows frames + OCR only.
- `--no-ocr` — skip OCR entirely.
- `--no-contact-sheet` / `--no-timeline` — skip those outputs.

### Saving disk space

`--no-source` deletes the **downloaded** source video once frames + transcript are
extracted. It never deletes a local file you provided as input. (By default the download
is kept so you can re-run with different settings without re-downloading.)

## 5. Cleaning up

Output folders persist on purpose (re-readable, auditable). Remove them when done:

```bash
./watch-video --clean <slug>          # one run, by its folder name under ./watch-video-out/
./watch-video --clean ./some/dir      # an explicit folder (e.g. a custom --out)
./watch-video --clean all             # every watch-video folder under ./watch-video-out/
./watch-video --clean-older-than 7    # everything older than 7 days
```

Cleanup is safe by design: it only touches folders that carry watch-video's hidden
`.watch-video.json` marker, deletes only watch-video's own files inside them, and leaves
the folder in place if it still contains files of yours.

**Ephemeral runs:** when you want nothing left behind, the agent command supports
`--ephemeral` — it runs, you (the agent) read the results, then it cleans the folder.

## 6. Choosing where output goes (`--out`) safely

By default each run gets its own folder under `./watch-video-out/`. If you pass `--out`
pointing at a directory that already has files and wasn't created by watch-video, the run
**refuses** (so it can't overwrite or later delete your files). Either point `--out` at a
new/empty directory, or pass `--force` if you really mean to write there.

## 7. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `ERROR: ffmpeg not found` | Install ffmpeg (`python3 scripts/setup.py`). |
| `yt-dlp produced no file` | The link is private — add `--cookies-from-browser <browser>`. |
| OCR section empty / no `ocr-combined.md` | `tesseract` isn't installed (OCR is skipped). Install it, or accept transcript+frames only. |
| First run is slow / needs network | First transcription downloads the Whisper model once, then caches it. Use a smaller `--model` (`base`/`tiny`) to speed up. |
| `refusing to write … non-empty directory` | Your `--out` has unrelated files; use a fresh dir or `--force`. |
| Blank/garbled on-screen numbers | Try `--ocr-tuned`; always verify against the frame image. |

## 8. Advanced: GPU transcription

The default is local CPU (int8) — portable, no GPU setup. For faster transcription on
NVIDIA (CUDA) or AMD/Apple (whisper.cpp + Vulkan/Metal), see
[`TRANSCRIPTION-BACKENDS.md`](TRANSCRIPTION-BACKENDS.md). The backend is isolated so it's a
drop-in swap.
