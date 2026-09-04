<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# Security policy

Report vulnerabilities privately to the maintainer. Include the affected version, input bytes,
selected format, observed behavior, and the smallest reproducer.

UniText parses untrusted text under explicit byte, node, nesting, and decoded-text limits. Release
builds retain Nim bounds and overflow checks. The C ABI traps exceptions and defects, rejects null
handles and inconsistent lengths, and never unwinds into foreign code. As with ordinary C APIs, an
arbitrary non-null pointer that was not returned by UniText is undefined caller behavior.

The C ABI is single-threaded. Call `unitext_init` before other entry points, externally serialize
calls, and destroy every document handle exactly once. Output buffer functions support a size-query
call followed by a caller-owned allocation.

The 1.x line receives compatibility-preserving fixes. Unsupported syntax is not a security bypass:
it remains text, survives as an extension, produces a diagnostic, or fails parsing.
