# Changelog

All notable changes to UniText are documented in this file.

The format follows Keep a Changelog, and this project follows Semantic Versioning.

## [0.2.0] - 2026-08-21

### Added

- A bounded neutral document model with stable node identifiers and immutable edits.
- Markdown, reStructuredText, AsciiDoc, and styled RTF subset codecs.
- Versioned JSON interchange and machine-readable loss diagnostics.
- A stable C ABI and a thin Cython-based Python binding.
- Debug and release tests, executable examples, API documentation, and an executable Book.
- Three-platform CI and future release workflows matching Uni Family conventions.
- Opaque immutable AST values, complete parsed-node source spans, and interchange schema version 2.
- Pinned official/differential corpus gates and deterministic continuous codec mutation fuzzing.
- Deterministic SPDX source SBOMs plus keyless release signatures and provenance/SBOM attestations.

### Security

- Explicit input, nesting, node, and decoded-text limits for untrusted document parsing.
- Strict Unicode-scalar UTF-8 validation and sanitized self-round-trip fuzz coverage.
