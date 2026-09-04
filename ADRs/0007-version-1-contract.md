<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0007: Version 1 compatibility contract

- Status: Accepted
- Date: 2026-08-21

Version 1 freezes the public Nim names, C symbols and numeric enums, Python names, interchange
schema version 2, stable node kinds, resource-limit behavior, deterministic serialization, and
explicit diagnostic contract.

The supported syntax is capability-described and fixture-backed. Version 1 does not claim full
implementation of each source-format specification. New portable structures may be added without
changing existing meanings; incompatible interchange or ABI changes require a new major version.
