# Changelog

## 1.1.1 — 2026-06-07
- **Cross-platform invocation:** the plugin runs the wrapper via `uv run` (the one
  required dependency) instead of a hardcoded `python3`, so it no longer assumes a
  `python3` on PATH — works on Linux/macOS/Windows.
- **Docs:** comprehensive release README + `docs/USER-GUIDE.md`; a Platform support table
  (Linux/macOS supported; **Windows not yet maintainer-tested** — please open an issue);
  supported-sources list (Loom, YouTube, Vimeo, TikTok, Instagram, X, + any `yt-dlp`
  site); marketplace `metadata.description`.
- Genericized dependency-install hints (no longer `dnf`-only); internal process docs
  (specs/plans) moved out of the published repo.

## 1.1.0 — 2026-06-07
- Packaged as a Claude Code / Codex / claude.ai-web skill (thin wrapper around the CLI).
- CLI additions (non-destructive): `.watch-video.json` manifest, `--clean`/`--clean-older-than`,
  `--no-source`, `timeline.md` on by default + `--no-timeline`, `--ocr-tuned`, `--no-transcribe`,
  stale-artifact reconciliation.
- New: `scripts/watch-run.py` wrapper, `scripts/setup.py` bootstrap, `scripts/build-skill.sh`,
  `SKILL.md`, `commands/watch.md`, plugin manifests, smoke tests.

## 1.0.0
- Initial single-file CLI: local Loom/URL/file → transcript + deduped frames + OCR.
