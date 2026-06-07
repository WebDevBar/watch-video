# Packaging as a Claude Code skill/plugin

> **Status: not yet built — this is the plan/target, to be brainstormed and
> spec'd before any code.** Today watch-video is a single-file `uv` CLI: the
> agent runs it and reads the output folder.

## The goal

Package watch-video as a native Claude Code skill/plugin so the agent **invokes
it and gets frames + transcript directly in-context**, instead of shelling out
to the CLI and then reading the output folder. The same bundle should also work
on claude.ai web (skill upload) and Codex.

We adopt the **packaging** the two reference plugins already solved
(see [REFERENCE-PLUGINS.md](REFERENCE-PLUGINS.md)) and keep our **content edge**
(local OCR, dedupe, faster-whisper, Loom-native — see [WHY.md](WHY.md)).

## Target layout (modelled on `mathiaschu/watch` + `bradautomates/claude-video`)

```
.claude-plugin/
  plugin.json            plugin manifest
  marketplace.json       marketplace metadata
.codex-plugin/           (optional) Codex packaging
SKILL.md                 the skill contract loaded across all surfaces
commands/
  watch.md               the /watch slash command
scripts/
  setup.py               zero-config dependency bootstrap (ffmpeg/tesseract/uv)
  watch-video            the existing single-file pipeline (or split out)
hooks/
.github/workflows/       CI + release (build the .skill bundle)
scripts/build-skill.sh   emit the distributable watch.skill
CHANGELOG.md  LICENSE  README.md
```

## Open questions for brainstorming / spec

- **In-context return shape.** How does the skill hand frames + transcript back
  to the agent — inline images + markdown, or a path the agent reads? Reconcile
  with our persistent output folder + `SUMMARY.md`.
- **Frame budgeting vs dedupe.** The reference plugins cap frames (2 fps floor,
  100 ceiling, `--start`/`--end` windowing). We dedupe instead. Do we keep both
  levers, or one? How do they interact under a token budget?
- **OCR surfacing.** Where does `ocr-combined.md` live in the in-context return
  so financial figures are obviously available to the agent?
- **Bootstrap.** Our deps are `uv` + ffmpeg + tesseract (+ faster-whisper via
  uv). Adapt `setup.py` to install these across macOS/Linux/Windows.
- **Privacy guardrails in the skill contract.** `SKILL.md` should state that
  transcription/OCR are local and that output folders contain sensitive data
  and must never be committed/uploaded.
- **GPU path.** Expose `--device` / backend selection (CPU → CUDA →
  whisper.cpp+Vulkan) per [TRANSCRIPTION-BACKENDS.md](TRANSCRIPTION-BACKENDS.md).

These are intentionally left open — they're the subject of the upcoming
brainstorming + spec pass, not decisions to make here.
