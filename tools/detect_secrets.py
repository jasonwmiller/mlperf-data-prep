#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "detect-secrets==1.5.0",
# ]
# ///
"""Run detect-secrets with this repo's baseline.

Usage:
  uv run tools/detect_secrets.py update
  uv run tools/detect_secrets.py check [files...]
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / ".secrets.baseline"
EXCLUDE_FILES = r"^(logs/|training_results_v5\.1/|\.git/|\.venv.*/)"


def run(args: list[str], *, stdout=None) -> int:
    return subprocess.run(args, cwd=ROOT, stdout=stdout, check=False).returncode


def update() -> int:
    with BASELINE.open("w", encoding="utf-8") as out:
        return run(
            [
                "detect-secrets",
                "scan",
                "--exclude-files",
                EXCLUDE_FILES,
            ],
            stdout=out,
        )


def check(files: list[str]) -> int:
    if not BASELINE.exists():
        print(f"missing baseline: {BASELINE}", file=sys.stderr)
        print("run: uv run tools/detect_secrets.py update", file=sys.stderr)
        return 1

    args = ["detect-secrets-hook", "--baseline", str(BASELINE)]
    args.extend(files)
    return run(args)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["update", "check"])
    parser.add_argument("files", nargs="*")
    args = parser.parse_args()

    if args.command == "update":
        return update()
    return check(args.files)


if __name__ == "__main__":
    raise SystemExit(main())
