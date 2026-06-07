# watch-video

**Give a coding agent the ability to "watch" a video — entirely on your own machine.**

`watch-video` turns a **Loom**, a **YouTube / Vimeo / TikTok / Instagram / X** link (or
any of the [~1000+ sites `yt-dlp` supports](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md)),
or a **local file** into artifacts an LLM agent can actually read:

- a **timestamped transcript** (local Whisper),
- a **deduplicated set of key frames** (so static screencasts don't waste tokens),
- **OCR of on-screen text** (so financial figures, dashboard numbers, and labels that
  are *shown but never spoken* survive), and
- a **`timeline.md`** that interleaves each frame with what was said and what was on
  screen at that moment.

It ships both as a **command-line tool** and as a **Claude Code / Codex plugin** (the
agent runs it for you and reads the result).

> **Everything runs locally** — `yt-dlp` + `ffmpeg` + `faster-whisper` + `tesseract`.
> No video or audio is sent to any cloud service. This is the whole point: recordings
> often contain private or financial data.
> Version: **1.1.0** · License: MIT

---

## Table of contents

- [Why](#why)
- [Install](#install)
  - [As a Claude Code plugin](#a-as-a-claude-code-plugin-recommended-for-agents)
  - [As a Codex skill](#b-as-a-codex-skill)
  - [As a CLI](#c-as-a-cli)
  - [claude.ai web bundle](#d-claudeai-web-bundle-non-sensitive-videos-only)
- [Quick start](#quick-start)
- [Output](#output-what-the-agent-reads)
- [Options](#options)
- [Cleanup & ephemeral mode](#cleanup--ephemeral-mode)
- [Privacy](#privacy)
- [How it works](#how-it-works)
- [Development](#development)
- [Credits](#credits)

---

## Why

Coding agents increasingly receive **screen recordings** instead of written tickets —
usually a Loom where someone points at a dashboard and says "change *this* number."
Those recordings carry sparse, non-technical instructions *and* on-screen figures that
are never spoken. To act on one, an agent needs the video as readable text + frames.

Existing video plugins either send audio to a **cloud** transcription API (a non-starter
for private/financial recordings) or have **no OCR** and **no frame de-duplication**.
`watch-video` is built for the local + Loom-native + on-screen-numbers case. See
[`docs/WHY.md`](docs/WHY.md) for the full rationale and a feature comparison, and
[`docs/REFERENCE-PLUGINS.md`](docs/REFERENCE-PLUGINS.md) for prior art / credits.

---

## Install

### Dependencies

| Tool | Required? | Purpose | Install |
|---|---|---|---|
| [`uv`](https://docs.astral.sh/uv/) | ✅ | runs the single-file script + its inline deps | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| `ffmpeg` | ✅ | frame extraction | `brew install ffmpeg` / `apt install ffmpeg` / `dnf install ffmpeg` |
| `tesseract` | optional | OCR of on-screen text | `brew install tesseract` / `apt install tesseract-ocr` / `dnf install tesseract` |

`yt-dlp`, `faster-whisper`, `Pillow`, `numpy`, `pytesseract` are pulled automatically by
`uv` on first run (pinned to Python 3.10–3.12). Or run the bootstrap:

```bash
python3 scripts/setup.py        # installs uv + ffmpeg (required) and tesseract (optional)
python3 scripts/setup.py --check  # verify only, no install
```

(On **Windows**, use `python` or `py` if `python3` isn't on your PATH.)

### Platform support

| Platform | Status | Notes |
|---|---|---|
| **Linux** | ✅ Supported | Primary dev/test platform. |
| **macOS** | ✅ Supported | `setup.py` uses Homebrew; all deps available. All paths are POSIX. |
| **Windows** (incl. Claude CLI in PowerShell) | ⚠️ Should work — not yet tested | The plugin invokes the tool through **`uv run`** (the one required dep), so it does **not** depend on a `python3` on PATH, and all paths use `pathlib`. `uv`, `ffmpeg`, `tesseract`, `yt-dlp`, and `faster-whisper` all have Windows builds (`setup.py` uses `winget`). Two caveats: (1) run the bare CLI as `uv run --script watch-video …` — the `./watch-video` shebang form is POSIX-only; (2) the **dev** scripts `tests/*.sh` and `scripts/build-skill.sh` are Bash, so they need **Git Bash or WSL** (end users don't run these). |

> **⚠️ Windows has not been tested.** The plugin install/run path is built on `uv` +
> `pathlib` specifically to be cross-platform, and Windows *should* work, but the
> maintainers have not verified it (macOS is also not maintainer-smoke-tested). **If you
> hit any issue on Windows (or macOS), please [open an issue](https://github.com/WebDevBar/watch-video/issues)
> and we'll try to address it.**

### A. As a Claude Code plugin (recommended for agents)

This repository **is** a single-plugin marketplace (`.claude-plugin/marketplace.json` at
its root). In Claude Code:

```
/plugin marketplace add webdevbar/watch-video
/plugin install watch-video@watch-video
```

(or `/plugin marketplace add /path/to/watch-video` for a local clone). Then invoke the
namespaced command on any video:

> Non-interactive equivalents (handy for scripting/CI): `claude plugin marketplace add webdevbar/watch-video` then `claude plugin install watch-video@watch-video`; `claude plugin validate .` checks the manifests.

```
/watch-video:watch https://www.loom.com/share/XXXX
/watch-video:watch ./recording.mp4 --no-ocr
```

The command runs the bundled CLI via a thin wrapper, applies sensible agent defaults
(tuned OCR on), prints the output directory, and the skill instructs the agent to read
the result in order. Dependencies: run `python3 scripts/setup.py` once (the plugin's
`SKILL.md` documents this).

### B. As a Codex skill

```bash
git clone https://github.com/webdevbar/watch-video ~/.codex/skills/watch-video
# or copy the built bundle (see Development → build-skill.sh)
```

The `.codex-plugin/plugin.json` manifest + shared `SKILL.md` drive it the same way.

### C. As a CLI

```bash
git clone https://github.com/webdevbar/watch-video
cd watch-video
chmod +x watch-video
./watch-video <loom-url | any-url | local-file.mp4> [options]
```

The shebang is `#!/usr/bin/env -S uv run --script`, so `uv` handles the environment.
**On Windows** (PowerShell/cmd) the shebang doesn't apply — run it explicitly:

```powershell
uv run --script watch-video <loom-url | any-url | local-file.mp4> [options]
```

### D. claude.ai web bundle (non-sensitive videos only)

`scripts/build-skill.sh` produces a `watch.skill` bundle you can upload at
**Settings → Capabilities → Skills**. ⚠️ The hosted web sandbox runs the pipeline on
Anthropic's servers, so the video **leaves your machine** — use the web surface for
**non-sensitive / public** videos only. Sensitive recordings stay on Claude Code/Codex.

---

## Quick start

**Through an agent (Claude Code):**

```
/watch-video:watch https://www.loom.com/share/abc123
```

**As a CLI:**

```bash
# a local file
./watch-video ./demo.mp4

# a public URL (YouTube, Vimeo, etc. — anything yt-dlp supports)
./watch-video "https://www.youtube.com/watch?v=XXXX"

# a private/team Loom or any login-gated source (reads your browser cookies locally)
./watch-video https://www.loom.com/share/XXXX --cookies-from-browser firefox

# denser sampling + sharper OCR for a number-heavy dashboard recording
./watch-video ./dashboard.mp4 --periodic 2 --ocr-tuned
```

**Sources:** local files, **Loom**, **YouTube**, **Vimeo**, **TikTok**, **Instagram**,
**X/Twitter**, and any other site [`yt-dlp` supports](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md).
Login-gated or private videos need `--cookies-from-browser <browser>` (or `--cookies cookies.txt`).

Output lands in `./watch-video-out/<slug>/` (override with `--out`). The CLI prints the
path to `SUMMARY.md` on stdout; everything else goes to stderr.

---

## Output (what the agent reads)

In `./watch-video-out/<slug>/`:

| File | What it is |
|---|---|
| `SUMMARY.md` | **Read first.** Run metadata + the exact list of artifacts produced + read order. |
| `timeline.md` | Each kept frame interleaved with the transcript line(s) spoken then + an OCR snippet. The primary comprehension doc. |
| `transcript.md` / `.txt` | Full timestamped transcript. |
| `frames/*.jpg` | The deduplicated key frames (timestamp in the filename). |
| `frames/ocr-combined.md` | All on-screen text, per frame. Cross-check exact numbers against the frame image (OCR can misread; the image is ground truth). |
| `frames/ocr/*.txt` | Per-frame raw OCR. |
| `contact-sheet.jpg` | A montage overview of all kept frames. |
| `.watch-video.json` | Hidden run manifest (tool signature, version, source, created, downloaded-source). Used as the ownership marker for safe cleanup — not for reading. |

**Read order** (skip any file a run didn't produce): `SUMMARY.md → timeline.md →
transcript.md → frames/*.jpg → frames/ocr-combined.md`.

---

## Options

| Flag | Default | Description |
|---|---|---|
| `--out DIR` | `./watch-video-out/<slug>` | exact output folder for this run |
| `--model NAME` | `small` | Whisper model: `tiny`/`base`/`small`/`medium`/`large-v3` |
| `--periodic SECONDS` | `4` | sample a frame every N seconds |
| `--scene-threshold FLOAT` | `0.08` | extra frame on scene change (0–1) |
| `--max-frames N` | `200` | strict cap on kept frames (evenly thinned, endpoints kept) |
| `--dedupe-distance N` | `6` | perceptual-hash distance to treat frames as duplicates |
| `--ocr-tuned` | off | upscale + threshold + tuned PSM for sharper on-screen-number OCR |
| `--no-ocr` | — | skip OCR |
| `--no-timeline` | — | skip `timeline.md` |
| `--no-contact-sheet` | — | skip the montage |
| `--no-transcribe` | — | skip transcription (no model download) |
| `--no-source` | — | delete the **downloaded** source video after extraction (never a local input) |
| `--language LANG` | auto | force transcription language (e.g. `en`) |
| `--cookies-from-browser B` | — | private Loom auth via browser cookies (`firefox`/`chrome`/…) |
| `--cookies FILE` | — | a Netscape `cookies.txt` for yt-dlp |
| `--force` | — | allow writing into a non-empty directory not created by watch-video |
| `--clean …` / `--clean-older-than DAYS` | — | janitorial cleanup (see below) |

> **Safety:** a run refuses to write into a **non-empty directory it didn't create**
> (use `--force` to override), so it never clobbers your files.

---

## Cleanup & ephemeral mode

Output folders persist (re-readable, auditable) and are gitignored. To remove them:

```bash
./watch-video --clean <slug>            # delete one run's folder (under ./watch-video-out/)
./watch-video --clean ./path/to/dir     # delete an explicit folder (custom --out)
./watch-video --clean all               # delete all watch-video folders under ./watch-video-out/
./watch-video --clean-older-than 7      # delete watch-video folders older than 7 days
```

Cleanup **only** deletes folders carrying a valid `.watch-video.json` signature, removes
**only** watch-video's own artifacts within them, and removes the folder itself only if
it's then empty — your files are never deleted.

**Ephemeral mode** (`/watch-video:watch … --ephemeral`) is a two-step, agent-driven flow:
the agent runs the tool, reads the artifacts into context, then runs
`watch-run.py --clean <dir>` to delete them — nothing sensitive lingers on disk.

---

## Privacy

- **Local-first.** On Claude Code and Codex (your machine), transcription + OCR never
  leave the device. No cloud transcription backend is ever used.
- **Web surface caveat.** The claude.ai web bundle runs in a hosted sandbox — for
  **non-sensitive / public videos only**.
- **Output is sensitive.** Folders may contain private/financial data; they're
  `.gitignore`d — never commit one. For private Loom links, cookies are read locally;
  never copy them into output/transcripts.

---

## How it works

```
acquire (local file | yt-dlp)
   → extract frames (first + scene-change + periodic, via ffmpeg)
   → dedupe (perceptual hash; strict --max-frames cap)
   → transcribe (faster-whisper, local CPU int8)   [skippable]
   → OCR each frame (tesseract)                     [optional]
   → contact sheet
   → timeline.md (interleave frames + transcript + OCR)
   → SUMMARY.md + .watch-video.json manifest
```

The transcription backend is isolated in one `transcribe()` function — a drop-in swap to
CUDA or whisper.cpp+Vulkan/Metal. See
[`docs/TRANSCRIPTION-BACKENDS.md`](docs/TRANSCRIPTION-BACKENDS.md).

The plugin layer is a **thin wrapper** (`scripts/watch-run.py`) around the unchanged CLI
— one implementation of the pipeline, never duplicated.

A step-by-step user guide lives in [`docs/USER-GUIDE.md`](docs/USER-GUIDE.md).

---

## Development

```bash
bash tests/run_all.sh                 # full suite (offline; tesseract optional)
WV_TRANSCRIBE_TEST=1 bash tests/transcribe_test.sh   # opt-in: exercises real Whisper
bash scripts/build-skill.sh dist/watch.skill         # build the distributable bundle
```

Tests are offline bash integration + unit tests against a synthetic clip (no network once
the `uv` cache is warm; `--no-transcribe` avoids the model download). The CLI is a single
file (`watch-video`); the wrapper/bootstrap/builder live in `scripts/`.

---

## Credits

Packaging modeled on, and with thanks to,
[`mathiaschu/watch`](https://github.com/mathiaschu/watch) and
[`bradautomates/claude-video`](https://github.com/bradautomates/claude-video). The OCR,
frame de-duplication, `timeline.md` interleave, and local faster-whisper backend are
watch-video's additions.

## License

MIT — see [`LICENSE`](LICENSE).
