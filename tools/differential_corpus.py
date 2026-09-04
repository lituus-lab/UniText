#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Compare UniText's supported semantic projection with a pinned Pandoc oracle."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


PANDOC_READERS = {
    "markdown": "commonmark",
    "rst": "rst",
    "asciidoc": "asciidoc",
    "rtf": "rtf",
}


def run(command: list[str], content: str = "") -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        input=content,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=30,
    )


def normalize_prose(value: str) -> str:
    return "\n".join(
        re.sub(r"[ \t\r\f\v]+", " ", line).strip()
        for line in value.strip().split("\n")
    )


def inline_text(nodes: list[dict[str, Any]]) -> str:
    result: list[str] = []
    for node in nodes:
        kind = node.get("t")
        value = node.get("c")
        if kind == "Str":
            result.append(value)
        elif kind in {"Space", "SoftBreak"}:
            result.append(" ")
        elif kind == "LineBreak":
            result.append("\n")
        elif kind in {"Code", "Math"}:
            result.append(value[1])
        elif kind in {"Emph", "Strong", "Strikeout", "Superscript", "Subscript"}:
            result.append(inline_text(value))
        elif kind in {"Link", "Image"}:
            result.append(inline_text(value[1]))
        elif kind == "Quoted":
            result.append(inline_text(value[1]))
        elif kind == "RawInline":
            result.append(value[1])
        elif kind == "Note":
            result.append(blocks_text(value))
        else:
            raise ValueError(f"unsupported Pandoc inline node: {kind}")
    return "".join(result)


def block_projection(block: dict[str, Any]) -> tuple[str, str]:
    kind = block.get("t")
    value = block.get("c")
    if kind == "Header":
        return "heading", normalize_prose(inline_text(value[2]))
    if kind in {"Para", "Plain"}:
        return "paragraph", normalize_prose(inline_text(value))
    if kind == "CodeBlock":
        return "code", value[1].rstrip("\n")
    if kind == "HorizontalRule":
        return "thematic_break", ""
    if kind == "BlockQuote":
        return "quote", blocks_text(value)
    if kind == "BulletList":
        return "unordered_list", "\n".join(blocks_text(item) for item in value)
    if kind == "OrderedList":
        return "ordered_list", "\n".join(blocks_text(item) for item in value[1])
    if kind in {"Div", "Figure"}:
        nested = value[-1]
        return "extension", blocks_text(nested)
    if kind == "RawBlock":
        return "extension", value[1]
    raise ValueError(f"unsupported Pandoc block node: {kind}")


def blocks_text(blocks: list[dict[str, Any]]) -> str:
    return "\n".join(block_projection(block)[1] for block in blocks)


def pandoc_projection(executable: str, reader: str, content: str) -> dict[str, Any]:
    result = run([executable, "--from", reader, "--to", "json"], content)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Pandoc failed without diagnostics")
    root = json.loads(result.stdout)
    projected = [block_projection(block) for block in root["blocks"]]
    return {
        "kinds": [kind for kind, _ in projected],
        "plain": "\n".join(value for _, value in projected),
    }


def unitext_projection(probe: Path, format_name: str, content: str) -> dict[str, Any]:
    result = run([str(probe), format_name], content)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "UniText probe failed without diagnostics")
    return json.loads(result.stdout)


def assert_projection(case_id: str, actor: str, actual: dict[str, Any],
                      expected: dict[str, Any]) -> None:
    if actual["kinds"] != expected["kinds"]:
        raise AssertionError(
            f"{case_id}: {actor} block kinds {actual['kinds']!r} != "
            f"{expected['kinds']!r}"
        )
    if normalize_prose(actual["plain"]) != normalize_prose(expected["plain"]):
        raise AssertionError(
            f"{case_id}: {actor} plain text {actual['plain']!r} != "
            f"{expected['plain']!r}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--probe", type=Path, required=True)
    parser.add_argument("--pandoc", default="pandoc")
    parser.add_argument("--pandoc-version", default="3.10.2")
    args = parser.parse_args()

    version = run([args.pandoc, "--version"])
    if version.returncode != 0:
        raise RuntimeError("the pinned Pandoc oracle is unavailable")
    first_line = version.stdout.splitlines()[0] if version.stdout else ""
    if first_line != f"pandoc {args.pandoc_version}":
        raise RuntimeError(
            f"Pandoc version mismatch: expected {args.pandoc_version!r}, got {first_line!r}"
        )

    corpus = json.loads(args.corpus.read_text(encoding="utf-8"))
    checked = 0
    skipped: list[str] = []
    for fixture in corpus["cases"]:
        case_id = fixture["id"]
        expected = {
            "kinds": fixture["expected_kinds"],
            "plain": fixture["expected_plain"],
        }
        unitext = unitext_projection(args.probe, fixture["format"], fixture["input"])
        assert_projection(case_id, "UniText", unitext, expected)
        if not unitext.get("source_maps_complete"):
            raise AssertionError(f"{case_id}: UniText emitted an incomplete source map")
        if unitext.get("diagnostic_errors") != 0:
            raise AssertionError(f"{case_id}: UniText emitted an error diagnostic")
        if not fixture.get("pandoc_differential", True):
            skipped.append(case_id)
            continue
        oracle = pandoc_projection(
            args.pandoc, PANDOC_READERS[fixture["format"]], fixture["input"]
        )
        assert_projection(case_id, "Pandoc", oracle, expected)
        checked += 1

    if checked < 20:
        raise AssertionError(f"too few differential cases: {checked}; expected at least 20")
    print(
        f"differential corpus: {checked} passed with Pandoc {args.pandoc_version}; "
        f"{len(skipped)} explicitly excluded ({', '.join(skipped) or 'none'})"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, KeyError, OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
