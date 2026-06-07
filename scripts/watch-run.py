#!/usr/bin/env python3
"""Thin wrapper the /watch command calls. Resolves + runs the bundled watch-video
CLI via `uv run --script`, applies /watch defaults, and prints exactly one stdout
line: the output directory. Holds no pipeline logic. See spec §9."""
import subprocess
import sys
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent  # CLI ships at the bundle root
CLI = SKILL_DIR / "watch-video"


def run_cli(extra_args, default_ocr_tuned):
    cmd = ["uv", "run", "--script", str(CLI)]
    if default_ocr_tuned and "--no-ocr" not in extra_args and "--ocr-tuned" not in extra_args:
        cmd.append("--ocr-tuned")
    cmd += extra_args
    # CLI prints exactly one stdout line: the SUMMARY.md path. stderr passes through.
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        sys.exit(proc.returncode)
    summary_line = (proc.stdout or "").strip().splitlines()[-1] if proc.stdout.strip() else ""
    if not summary_line:
        sys.exit("watch-run: CLI produced no output path")
    return str(Path(summary_line).parent)


def run_cleanup(clean_args):
    # clean_args is already filtered to ONLY cleanup flags + their values.
    cmd = ["uv", "run", "--script", str(CLI)] + clean_args
    sys.exit(subprocess.run(cmd).returncode)


def _extract_cleanup_args(argv):
    """Keep ONLY --clean/--clean-older-than (+ their value); drop everything else
    (e.g. wrapper-only --ephemeral, processing defaults) so the janitorial CLI run is clean."""
    out, i = [], 0
    while i < len(argv):
        a = argv[i]
        if a in ("--clean", "--clean-older-than"):
            out.append(a)
            if i + 1 < len(argv):
                out.append(argv[i + 1]); i += 1
        i += 1
    return out


def main(argv):
    # Cleanup pass-through: `watch-run.py --clean <dir>` / `--clean-older-than N`
    if "--clean" in argv or "--clean-older-than" in argv:
        run_cleanup(_extract_cleanup_args(argv))
        return
    # Processing run: intercept --ephemeral (wrapper-only; not a CLI flag).
    extra = [a for a in argv if a != "--ephemeral"]
    out_dir = run_cli(extra, default_ocr_tuned=True)
    print(out_dir)  # the one and only wrapper stdout line


if __name__ == "__main__":
    main(sys.argv[1:])
