<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0001: Acyclic document-engine layers

- Status: Accepted
- Date: 2026-08-21

The model is the lowest layer. Format detection and codec contracts depend on the model; codecs
implement those contracts; interchange and edits operate on the model; dispatch combines codecs;
the C ABI is the outermost engine surface. No module depends on a UI or application.

`nimble checkVGraph` enforces the declared direction. UniText has no Uni-family engine dependency.
