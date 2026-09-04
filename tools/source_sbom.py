#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Generate and verify a deterministic SPDX 2.3 source SBOM."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tempfile


MAX_FILES = 100_000
MAX_TOTAL_BYTES = 1 * 1024 * 1024 * 1024
CHUNK_BYTES = 1024 * 1024


class SbomError(ValueError):
    """Raised when source inventory or SBOM validation fails."""


def git(root: Path, *arguments: str) -> bytes:
    try:
        return subprocess.run(
            ["git", "-C", str(root), *arguments],
            check=True,
            capture_output=True,
            timeout=30,
        ).stdout
    except (OSError, subprocess.SubprocessError) as error:
        raise SbomError(f"git inventory failed: {error}") from error


def source_paths(root: Path, output: Path | None = None) -> list[Path]:
    raw = git(root, "ls-files", "--cached", "--others", "--exclude-standard", "-z")
    result: list[Path] = []
    total = 0
    output = output.resolve() if output else None
    for encoded in raw.split(b"\0"):
        if not encoded:
            continue
        try:
            relative = encoded.decode("utf-8", errors="strict")
        except UnicodeDecodeError as error:
            raise SbomError("source path is not valid UTF-8") from error
        portable = PurePosixPath(relative)
        if portable.is_absolute() or any(part in {"", ".", ".."} for part in portable.parts):
            raise SbomError(f"unsafe source path: {relative!r}")
        path = root.joinpath(*portable.parts)
        if output is not None and path.resolve() == output:
            continue
        # A dirty but reviewable working tree may contain intentional tracked
        # deletions. They are absent from the source being inventoried.
        if not path.exists() and not path.is_symlink():
            continue
        if path.is_symlink():
            raise SbomError(f"symbolic links require explicit packaging policy: {relative}")
        if not path.is_file():
            raise SbomError(f"inventory entry is not a regular file: {relative}")
        total += path.stat().st_size
        if total > MAX_TOTAL_BYTES:
            raise SbomError("source inventory byte limit exceeded")
        result.append(path)
    if len(result) > MAX_FILES:
        raise SbomError("source inventory file-count limit exceeded")
    return sorted(result, key=lambda item: item.relative_to(root).as_posix())


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(CHUNK_BYTES), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_spdx_id(relative: str) -> str:
    return "SPDXRef-File-" + hashlib.sha256(relative.encode("utf-8")).hexdigest()[:24]


def created_at(root: Path) -> str:
    raw = git(root, "log", "-1", "--format=%ct").decode("ascii").strip()
    try:
        timestamp = int(raw)
    except ValueError as error:
        raise SbomError("repository commit time is unavailable") from error
    return datetime.fromtimestamp(timestamp, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def generate(root: Path, name: str, version: str, output: Path) -> dict:
    root = root.resolve(strict=True)
    output = output.resolve()
    files = source_paths(root, output)
    records = []
    verification_values = []
    relationships = [{
        "spdxElementId": "SPDXRef-DOCUMENT",
        "relationshipType": "DESCRIBES",
        "relatedSpdxElement": "SPDXRef-Package",
    }]
    namespace_digest = hashlib.sha256()
    for path in files:
        relative = path.relative_to(root).as_posix()
        digest = sha256(path)
        namespace_digest.update(relative.encode("utf-8") + b"\0" + digest.encode("ascii") + b"\n")
        verification_values.append(digest)
        identifier = file_spdx_id(relative)
        records.append({
            "fileName": "./" + relative,
            "SPDXID": identifier,
            "checksums": [{"algorithm": "SHA256", "checksumValue": digest}],
            "licenseConcluded": "NOASSERTION",
            "copyrightText": "NOASSERTION",
        })
        relationships.append({
            "spdxElementId": "SPDXRef-Package",
            "relationshipType": "CONTAINS",
            "relatedSpdxElement": identifier,
        })
    package_verification = hashlib.sha1(
        "".join(sorted(verification_values)).encode("ascii")
    ).hexdigest()
    document = {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": f"{name}-{version}-source",
        "documentNamespace": (
            f"https://spdx.org/spdxdocs/{name}-{version}-"
            + namespace_digest.hexdigest()
        ),
        "creationInfo": {
            "created": created_at(root),
            "creators": ["Tool: lituus-source-sbom/1"],
        },
        "packages": [{
            "name": name,
            "SPDXID": "SPDXRef-Package",
            "versionInfo": version,
            "downloadLocation": "NOASSERTION",
            "filesAnalyzed": True,
            "packageVerificationCode": {
                "packageVerificationCodeValue": package_verification,
            },
            "licenseConcluded": "NOASSERTION",
            "licenseDeclared": "NOASSERTION",
            "copyrightText": "NOASSERTION",
        }],
        "files": records,
        "relationships": relationships,
    }
    encoded = json.dumps(document, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{output.name}.", suffix=".tmp", dir=output.parent
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, output)
        if hasattr(os, "O_DIRECTORY"):
            descriptor = os.open(output.parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
    finally:
        if temporary.exists():
            temporary.unlink()
    return document


def verify(root: Path, sbom_path: Path) -> dict:
    root = root.resolve(strict=True)
    try:
        document = json.loads(sbom_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SbomError(f"cannot read SPDX document: {error}") from error
    required_document_fields = {
        "spdxVersion", "dataLicense", "SPDXID", "name", "documentNamespace",
        "creationInfo", "packages", "files", "relationships",
    }
    if set(document) != required_document_fields:
        raise SbomError("invalid SPDX document fields")
    if (
        document.get("spdxVersion") != "SPDX-2.3"
        or document.get("dataLicense") != "CC0-1.0"
        or document.get("SPDXID") != "SPDXRef-DOCUMENT"
    ):
        raise SbomError("unsupported SPDX document header")
    records = document.get("files")
    if not isinstance(records, list) or len(records) > MAX_FILES:
        raise SbomError("invalid SPDX file inventory")
    actual = {
        "./" + path.relative_to(root).as_posix(): sha256(path)
        for path in source_paths(root, sbom_path)
    }
    recorded: dict[str, str] = {}
    for record in records:
        if not isinstance(record, dict) or set(record) != {
            "fileName", "SPDXID", "checksums", "licenseConcluded", "copyrightText"
        }:
            raise SbomError("invalid SPDX file record")
        name = record.get("fileName")
        checksums = record.get("checksums")
        if not isinstance(name, str) or not isinstance(checksums, list):
            raise SbomError("incomplete SPDX file record")
        matches = [
            item.get("checksumValue")
            for item in checksums
            if isinstance(item, dict) and item.get("algorithm") == "SHA256"
        ]
        if (
            len(matches) != 1
            or len(checksums) != 1
            or name in recorded
            or not name.startswith("./")
            or record.get("SPDXID") != file_spdx_id(name[2:])
            or record.get("licenseConcluded") != "NOASSERTION"
            or record.get("copyrightText") != "NOASSERTION"
        ):
            raise SbomError(f"invalid SPDX checksum record: {name!r}")
        recorded[name] = matches[0]
    if recorded != actual:
        missing = sorted(actual.keys() - recorded.keys())
        stale = sorted(recorded.keys() - actual.keys())
        changed = sorted(key for key in actual.keys() & recorded.keys() if actual[key] != recorded[key])
        raise SbomError(
            f"source inventory mismatch (missing={missing}, stale={stale}, changed={changed})"
        )
    packages = document.get("packages")
    if not isinstance(packages, list) or len(packages) != 1:
        raise SbomError("SPDX document requires exactly one package")
    package = packages[0]
    if not isinstance(package, dict) or set(package) != {
        "name", "SPDXID", "versionInfo", "downloadLocation", "filesAnalyzed",
        "packageVerificationCode", "licenseConcluded", "licenseDeclared",
        "copyrightText",
    }:
        raise SbomError("invalid SPDX package")
    if (
        not isinstance(package.get("name"), str)
        or not package["name"]
        or not isinstance(package.get("versionInfo"), str)
        or not package["versionInfo"]
        or package.get("SPDXID") != "SPDXRef-Package"
        or package.get("downloadLocation") != "NOASSERTION"
        or package.get("filesAnalyzed") is not True
        or package.get("licenseConcluded") != "NOASSERTION"
        or package.get("licenseDeclared") != "NOASSERTION"
        or package.get("copyrightText") != "NOASSERTION"
    ):
        raise SbomError("invalid SPDX package contract")
    expected_verification = hashlib.sha1(
        "".join(sorted(actual.values())).encode("ascii")
    ).hexdigest()
    if package.get("packageVerificationCode") != {
        "packageVerificationCodeValue": expected_verification
    }:
        raise SbomError("SPDX package verification code mismatch")
    namespace_digest = hashlib.sha256()
    for name, digest in sorted(actual.items()):
        namespace_digest.update(
            name[2:].encode("utf-8") + b"\0" + digest.encode("ascii") + b"\n"
        )
    expected_namespace = (
        f"https://spdx.org/spdxdocs/{package['name']}-{package['versionInfo']}-"
        + namespace_digest.hexdigest()
    )
    if document.get("name") != f"{package['name']}-{package['versionInfo']}-source":
        raise SbomError("SPDX document name mismatch")
    if document.get("documentNamespace") != expected_namespace:
        raise SbomError("SPDX document namespace mismatch")
    if document.get("creationInfo") != {
        "created": created_at(root),
        "creators": ["Tool: lituus-source-sbom/1"],
    }:
        raise SbomError("SPDX creation provenance mismatch")
    expected_relationships = [{
        "spdxElementId": "SPDXRef-DOCUMENT",
        "relationshipType": "DESCRIBES",
        "relatedSpdxElement": "SPDXRef-Package",
    }]
    expected_relationships.extend({
        "spdxElementId": "SPDXRef-Package",
        "relationshipType": "CONTAINS",
        "relatedSpdxElement": file_spdx_id(name[2:]),
    } for name in sorted(actual))
    if document.get("relationships") != expected_relationships:
        raise SbomError("SPDX relationships mismatch")
    return document


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    create = subparsers.add_parser("create")
    create.add_argument("--root", type=Path, default=Path.cwd())
    create.add_argument("--name", required=True)
    create.add_argument("--version", required=True)
    create.add_argument("--output", required=True, type=Path)
    check = subparsers.add_parser("verify")
    check.add_argument("--root", type=Path, default=Path.cwd())
    check.add_argument("--sbom", required=True, type=Path)
    arguments = parser.parse_args()
    try:
        if arguments.command == "create":
            document = generate(arguments.root, arguments.name, arguments.version, arguments.output)
        else:
            document = verify(arguments.root, arguments.sbom)
    except SbomError as error:
        print(f"source-sbom: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"files": len(document["files"]), "status": "ok"}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
