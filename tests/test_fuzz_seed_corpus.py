# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "build_fuzz_seed_corpus", ROOT / "tools" / "build_fuzz_seed_corpus.py"
)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FuzzSeedCorpusTests(unittest.TestCase):
    def test_build_is_deterministic_and_covers_every_format_target_pair(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "corpus"
            count, digest = MODULE.build(
                ROOT / "fixtures" / "official" / "cases-v1.json", output
            )
            first = {path.name: path.read_bytes() for path in output.iterdir()}
            rebuilt_count, rebuilt_digest = MODULE.build(
                ROOT / "fixtures" / "official" / "cases-v1.json", output
            )
            second = {path.name: path.read_bytes() for path in output.iterdir()}
            self.assertEqual(count, 5 * 23 + 1)
            self.assertEqual((count, digest, first), (rebuilt_count, rebuilt_digest, second))
            self.assertEqual({payload[0] for payload in first.values()}, set(range(6)))
            self.assertEqual({payload[1] for payload in first.values()}, set(range(4)))

    def test_refuses_non_file_entries_in_existing_destination(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "corpus"
            output.mkdir()
            (output / "unexpected").mkdir()
            with self.assertRaisesRegex(ValueError, "unexpected corpus entry"):
                MODULE.build(ROOT / "fixtures" / "official" / "cases-v1.json", output)


if __name__ == "__main__":
    unittest.main()
