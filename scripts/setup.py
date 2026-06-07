#!/usr/bin/env python3
"""Per-OS bootstrap for watch-video. Ensures uv + ffmpeg (required) and tesseract
(optional, warn-only). `--check` only verifies, never installs. See spec §8."""
import argparse
import platform
import shutil
import subprocess
import sys
from pathlib import Path

UV_INSTALL = "https://docs.astral.sh/uv/getting-started/installation/"


def have(b):
    return shutil.which(b) is not None


def install_uv():
    """Attempt the official uv installer (spec §8). Returns True if uv ends up present."""
    sysname = platform.system()
    if sysname == "Windows":
        cmd = ["powershell", "-ExecutionPolicy", "ByPass", "-c",
               "irm https://astral.sh/uv/install.ps1 | iex"]
    else:
        cmd = ["sh", "-c", "curl -LsSf https://astral.sh/uv/install.sh | sh"]
    print(f"[setup] installing uv: {' '.join(cmd)}")
    try:
        subprocess.run(cmd, check=False)
    except Exception as e:
        print(f"[setup] uv install attempt errored: {e}", file=sys.stderr)
    # uv installs to ~/.local/bin or ~/.cargo/bin — may not be on PATH this process; re-check both.
    if have("uv"):
        return True
    for p in (Path.home() / ".local/bin/uv", Path.home() / ".cargo/bin/uv"):
        if p.exists():
            print(f"[setup] uv installed at {p} — ensure its dir is on PATH, then re-run.",
                  file=sys.stderr)
            return False
    return False


def pkg_install(pkg):
    sysname = platform.system()
    if sysname == "Darwin" and have("brew"):
        return ["brew", "install", pkg]
    if sysname == "Linux":
        if have("dnf"):
            return ["sudo", "dnf", "install", "-y", pkg]
        if have("apt-get"):
            return ["sudo", "apt-get", "install", "-y", pkg]
    if sysname == "Windows" and have("winget"):
        return ["winget", "install", pkg]
    return None


def ensure(pkg, required, check_only):
    if have(pkg):
        print(f"[setup] {pkg}: present")
        return True
    if check_only:
        msg = f"[setup] {pkg}: MISSING"
        print(msg, file=sys.stderr)
        return not required
    cmd = pkg_install(pkg)
    if cmd is None:
        print(f"[setup] {pkg}: no supported package manager — install it manually.",
              file=sys.stderr)
        return not required
    print(f"[setup] installing {pkg}: {' '.join(cmd)}")
    ok = subprocess.run(cmd).returncode == 0 and have(pkg)
    if not ok and required:
        print(f"[setup] FAILED to install required {pkg}.", file=sys.stderr)
    return ok or (not required)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="verify only, do not install")
    args = ap.parse_args()

    ok = True
    if have("uv"):
        print("[setup] uv: present")
    elif args.check:
        print(f"[setup] uv: MISSING — install: {UV_INSTALL}", file=sys.stderr)
        ok = False
    else:
        # Attempt the official installer (spec §8). If it lands off-PATH, tell the user.
        if not install_uv():
            print(f"[setup] uv could not be made available on PATH. See: {UV_INSTALL}",
                  file=sys.stderr)
            ok = False

    ok = ensure("ffmpeg", required=True, check_only=args.check) and ok
    ensure("tesseract", required=False, check_only=args.check)  # optional: warn-only

    if not ok:
        print("[setup] one or more REQUIRED prerequisites are missing.", file=sys.stderr)
        sys.exit(1)
    print("[setup] required prerequisites satisfied (uv + ffmpeg). tesseract optional.")


if __name__ == "__main__":
    main()
