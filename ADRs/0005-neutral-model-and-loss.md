<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0005: Neutral semantics and explicit loss

- Status: Accepted
- Date: 2026-08-21

Conversion passes through one semantic document tree. Pairwise format translators are rejected.
The tree represents portable meaning; format syntax and frontend state do not enter it.

Unsupported constructs must remain source text, become extension nodes, produce diagnostics, or
fail explicitly. Serializers report every normalization they perform. The versioned JSON
interchange preserves node identifiers and is the stable process boundary.
