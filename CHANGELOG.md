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
