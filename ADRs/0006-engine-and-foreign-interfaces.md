<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0006: Engine and foreign interfaces

- Status: Accepted
- Date: 2026-08-21

The Nim library is the engine. A hand-written C header exposes opaque document handles, numeric
format identifiers, buffer-write-with-retry operations, and stable error inspection. The library
uses ARC and retains runtime checks because it parses untrusted bytes.

The Python package is a Cython binding over the C ABI. It does not reimplement parsing. Editors,
renderers, converters, and other applications remain separate consumers.
