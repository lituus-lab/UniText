#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Build libFuzzer seeds from the pinned, license-documented official corpus."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import tempfile
from pathlib import Path


FORMAT_MODE = {"markdown": 0, "rst": 1, "asciidoc": 2, "rtf": 3}
EMPTY_INTERCHANGE = (
    b'{"schema":"unitext.document","version":2,"metadata":{},'
    b'"span":null,"blocks":[]}'
)


def safe_replace_directory(staging: Path, destination: Path) -> None:
    if destination.exists():
        if destination.is_symlink() or not destination.is_dir():
            raise ValueError(f"refusing unsafe output path: {destination}")
        for entry in destination.iterdir():
            if entry.is_symlink() or not entry.is_file():
                raise ValueError(f"refusing unexpected corpus entry: {entry}")
        shutil.rmtree(destination)
    os.replace(staging, destination)


def build(corpus_path: Path, output: Path) -> tuple[int, str]:
    raw = corpus_path.read_bytes()
    corpus = json.loads(raw)
    if corpus.get("schema") != "unitext.official-corpus" or corpus.get("version") != 1:
        raise ValueError("unsupported official corpus schema")
    cases = corpus.get("cases")
    if not isinstance(cases, list) or not cases:
        raise ValueError("official corpus has no cases")

    output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=f".{output.name}.", dir=output.parent))
    try:
        count = 0
        seen_ids: set[str] = set()
        for case_index, fixture in enumerate(cases):
            case_id = fixture["id"]
            if case_id in seen_ids:
                raise ValueError(f"duplicate case id: {case_id}")
            seen_ids.add(case_id)
            mode = FORMAT_MODE[fixture["format"]]
            payload = fixture["input"].encode("utf-8")
            for target in range(1, 5):
                seed = bytes((mode, target - 1)) + payload
                digest = hashlib.sha256(seed).hexdigest()
                (staging / f"{case_id}-{target}-{digest[:12]}").write_bytes(seed)
                count += 1

            auto_target = case_index % 4
            auto_seed = bytes((4, auto_target)) + payload
            digest = hashlib.sha256(auto_seed).hexdigest()
            (staging / f"{case_id}-auto-{digest[:12]}").write_bytes(auto_seed)
            count += 1

        interchange_seed = bytes((5, 0)) + EMPTY_INTERCHANGE
        digest = hashlib.sha256(interchange_seed).hexdigest()
        (staging / f"interchange-empty-{digest[:12]}").write_bytes(interchange_seed)
        count += 1
        safe_replace_directory(staging, output)
        staging = Path()
        return count, hashlib.sha256(raw).hexdigest()
    finally:
        if staging != Path() and staging.exists():
            shutil.rmtree(staging)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    count, digest = build(args.corpus.resolve(), args.output.resolve())
    print(f"fuzz seed corpus: {count} seeds; source_sha256={digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
