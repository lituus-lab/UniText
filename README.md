<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# UniText

UniText 0.2.0 is an experimental bounded structured-document I/O engine for Nim. It detects, parses, serializes,
edits, and converts a documented subset of Markdown, reStructuredText, AsciiDoc, and styled RTF
through one neutral semantic tree.

Its central guarantee is explicit loss. Unsupported content is retained as text or an extension,
reported by a diagnostic, or rejected. A conversion never silently deletes syntax it cannot
represent.

## Surfaces

- Nim API with capability-bearing codecs and explicit resource limits;
- versioned JSON interchange for process and language boundaries;
- stable C ABI with opaque handles and caller-owned output buffers;
- Cython Python binding over the C ABI;
- executable Book and generated Nim API reference.

## Module map

- `model`: bounded neutral document tree and validation;
- `codecs`: Markdown, reStructuredText, AsciiDoc, and styled RTF subsets;
- `interchange`: versioned JSON representation;
- `edit`: immutable structural edits;
- `c_api`: stable C ABI used by the Python binding.

## Uni-Family relationship

UniText is the format and document layer. It is independent from UniContext and UniDatabase, while
sharing the Uni-Family conventions for versioning, bounded inputs, provenance, and reproducible
tests.

## Development provenance

The implementation is maintained in Nim. Generated API documentation and bindings are derived
artifacts; Markdown source and tests remain authoritative. No external model or generated answer
is treated as a source of correctness.

## Nim example

~~~nim
import UniText

let source = "# Portable document\n\nText with **strong meaning**.\n"
echo convertDocument(source, formatMarkdown, formatAsciiDoc).content
~~~

Verified output:

~~~text
= Portable document

Text with *strong meaning*.
~~~

## Compatibility boundary

Version 1 freezes the public node kinds, interchange schema version 2, C ABI symbols and numeric
format identifiers, Python names, deterministic serialization, and resource-limit behavior. It
does not claim complete compatibility with every revision or extension of the four source formats.
See [the validation record](docs/validation.md) and [the version contract](ADRs/0004-version-1-contract.md).
The C ABI and Python binding expose both plain serialization and machine-readable serialization
reports so applications can make loss handling explicit.

## Gates

~~~sh
nimble testAll
nimble pyTest
nimble example
nimble cexample
nimble lint
nimble checkVGraph
nimble docs
nimble differential
nimble fuzzSmoke
nimble sbom
~~~

`differential` requires exactly Pandoc 3.10.2. CI installs the official Linux archive only after
checking its pinned SHA-256. `fuzzSmoke` is the short deterministic gate; the scheduled workflow
adds ASan/UBSan and a rotating long-run seed. `sbom` creates and then independently verifies the
deterministic SPDX 2.3 source inventory.

This workspace copy remains private and no publication has been performed. The release workflow
only becomes active after a repository and a version tag explicitly exist. That workflow assembles
checksums and an artifact SBOM, signs the checksum manifest with Sigstore keyless OIDC, verifies the
signature, and emits portable GitHub build-provenance and SBOM attestation bundles before release.
