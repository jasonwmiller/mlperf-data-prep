#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Create an aria2 URL list from the official MLCommons CC12M metadata."""

from __future__ import annotations

import argparse
import math
import sys
import urllib.request
from pathlib import Path


DEFAULT_URI_URL = (
    "https://training.mlcommons-storage.org/metadata/flux-1-cc12m-preprocessed.uri"
)
DEFAULT_MD5_URL = (
    "https://raw.githubusercontent.com/mlcommons/r2-infra/main/"
    "training/metadata/flux-1-cc12m-preprocessed.md5"
)


def fetch_text(url: str) -> str:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "mlperf-data-prep/1.0"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode("utf-8")


def parse_md5(md5_text: str) -> list[tuple[str, str]]:
    entries: list[tuple[str, str]] = []
    for line_number, line in enumerate(md5_text.splitlines(), start=1):
        if not line.strip():
            continue
        parts = line.split()
        if len(parts) != 2:
            raise ValueError(f"invalid md5 line {line_number}: {line}")
        checksum, filename = parts
        entries.append((checksum, filename.removeprefix("./")))
    return entries


def choose_range(
    total: int,
    *,
    start_line: int | None,
    end_line: int | None,
    partition_index: int,
    partitions: int,
) -> tuple[int, int]:
    if start_line is not None or end_line is not None:
        start = start_line or 1
        end = end_line or total
    else:
        if partitions < 1:
            raise ValueError("--partitions must be >= 1")
        if partition_index < 1 or partition_index > partitions:
            raise ValueError("--partition-index must be between 1 and --partitions")
        chunk = math.ceil(total / partitions)
        start = ((partition_index - 1) * chunk) + 1
        end = min(partition_index * chunk, total)

    if start < 1 or end < start or end > total:
        raise ValueError(f"invalid line range {start}-{end} for {total} entries")
    return start, end


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate aria2 input URLs for a slice of MLCommons FLUX CC12M."
    )
    parser.add_argument("--uri-url", default=DEFAULT_URI_URL)
    parser.add_argument("--md5-url", default=DEFAULT_MD5_URL)
    parser.add_argument("--output", type=Path, help="write URL list to this file")
    parser.add_argument(
        "--arrow-only",
        action="store_true",
        help="include only data-*.arrow files, skipping dataset metadata files",
    )
    parser.add_argument("--start-line", type=int)
    parser.add_argument("--end-line", type=int)
    parser.add_argument("--partitions", type=int, default=2)
    parser.add_argument("--partition-index", type=int, default=2)
    args = parser.parse_args()

    base_url = fetch_text(args.uri_url).strip().rstrip("/")
    entries = parse_md5(fetch_text(args.md5_url))
    if args.arrow_only:
        entries = [(checksum, filename) for checksum, filename in entries if filename.endswith(".arrow")]
    start, end = choose_range(
        len(entries),
        start_line=args.start_line,
        end_line=args.end_line,
        partition_index=args.partition_index,
        partitions=args.partitions,
    )

    urls = [f"{base_url}/{filename}" for _, filename in entries[start - 1 : end]]
    output = "\n".join(urls) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output, encoding="utf-8")
    else:
        sys.stdout.write(output)

    print(
        f"wrote {len(urls)} URLs from entries {start}-{end} of {len(entries)}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
