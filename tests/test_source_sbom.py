# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Adversarial tests for the deterministic SPDX source inventory."""

from __future__ import annotations

import hashlib
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

    def test_non_object_json_is_an_sbom_error(self):
        """`null`, a number and a list are valid JSON and not documents.

        `set(document)` raised TypeError on each, which `main` does not catch,
        so the verifier printed a traceback rather than its failure message.
        """
        with tempfile.TemporaryDirectory() as temporary:
            root = self.repository(Path(temporary))
            for payload in ("null", "42", "[]", '"text"'):
                output = root / "build" / "sbom.json"
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_text(payload, encoding="utf-8")
                with self.assertRaises(SBOM.SbomError):
                    SBOM.verify(root, output)

    def test_every_file_carries_the_spdx_required_sha1(self):
        """SPDX 2.3 asks for a SHA-1 per file and builds the package
        verification code from those, sorted and concatenated."""
        with tempfile.TemporaryDirectory() as temporary:
            root = self.repository(Path(temporary))
            output = root / "build" / "sbom.json"
            SBOM.generate(root, "Probe", "0.0.1", output)
            document = json.loads(output.read_text(encoding="utf-8"))
            algorithms = {
                item["algorithm"]
                for record in document["files"]
                for item in record["checksums"]
            }
            self.assertEqual(algorithms, {"SHA1", "SHA256"})

            ones = sorted(
                item["checksumValue"]
                for record in document["files"]
                for item in record["checksums"]
                if item["algorithm"] == "SHA1"
            )
            expected = hashlib.sha1("".join(ones).encode("ascii")).hexdigest()
            self.assertEqual(
                document["packages"][0]["packageVerificationCode"][
                    "packageVerificationCodeValue"
                ],
                expected,
            )


if __name__ == "__main__":
    unittest.main()
