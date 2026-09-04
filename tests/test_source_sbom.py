# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Adversarial tests for the deterministic SPDX source inventory."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


MODULE_PATH = Path(__file__).parent.parent / "tools" / "source_sbom.py"
SPEC = importlib.util.spec_from_file_location("source_sbom", MODULE_PATH)
SBOM = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(SBOM)


class SourceSbomTests(unittest.TestCase):
    def repository(self, directory: Path) -> Path:
        subprocess.run(["git", "init", "--quiet", str(directory)], check=True)
        subprocess.run(
            ["git", "-C", str(directory), "config", "user.name", "SBOM Test"],
            check=True,
        )
        subprocess.run(
            ["git", "-C", str(directory), "config", "user.email", "sbom@example.invalid"],
            check=True,
        )
        subprocess.run(
            ["git", "-C", str(directory), "config", "commit.gpgsign", "false"],
            check=True,
        )
        (directory / "source.nim").write_text("discard\n", encoding="utf-8")
        subprocess.run(["git", "-C", str(directory), "add", "source.nim"], check=True)
        subprocess.run(
            ["git", "-C", str(directory), "commit", "--quiet", "-m", "fixture"],
            check=True,
        )
        return directory

    def test_round_trip_and_source_change_detection(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.repository(Path(temporary))
            output = root / "build" / "source.spdx.json"
            SBOM.generate(root, "Fixture", "1.0.0", output)
            SBOM.verify(root, output)
            (root / "source.nim").write_text("echo 1\n", encoding="utf-8")
            with self.assertRaises(SBOM.SbomError):
                SBOM.verify(root, output)

    def test_rejects_tampered_package_and_relationships(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.repository(Path(temporary))
            output = root / "build" / "source.spdx.json"
            for field in ("package", "relationships"):
                SBOM.generate(root, "Fixture", "1.0.0", output)
                document = json.loads(output.read_text(encoding="utf-8"))
                if field == "package":
                    document["packages"][0]["packageVerificationCode"][
                        "packageVerificationCodeValue"
                    ] = "0" * 40
                else:
                    document["relationships"].pop()
                output.write_text(json.dumps(document), encoding="utf-8")
                with self.assertRaises(SBOM.SbomError):
                    SBOM.verify(root, output)


if __name__ == "__main__":
    unittest.main()
