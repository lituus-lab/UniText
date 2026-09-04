<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0004: UniText conventions

- Status: Accepted
- Date: 2026-07-15
- Scope: UniText

## Layout

```text
UniText.nimble              package + tasks
config.nims                 arch-conditional build flags
src/UniText.nim             umbrella
src/UniText/model.nim       the neutral document tree and its limits
src/UniText/codec.nim       what a codec declares, and the results it returns
src/UniText/codecs/         markdown, reStructuredText, AsciiDoc, RTF
src/UniText/detect.nim      format detection, with a confidence
src/UniText/io.nim          parse, serialize, convert
src/UniText/edit.nim        immutable edits
src/UniText/interchange.nim the JSON form of the tree
src/UniText/report.nim      diagnostics, rendered
src/UniText/c_api.nim       C ABI
include/UniText.h           hand-written C header
tests/ tests/c/             Nim + C ABI tests
tests/fuzz/ fixtures/       the mutation corpora and the pinned official one
examples/                   Nim + C demos
py/                         Cython binding + pytest
book/                       nimib book, code blocks run at build
ADRs/                       0001-0007
.github/workflows/ci.yml    3-OS Nim + C ABI + Python
LICENSE NOTICE CONTRIBUTING.md SECURITY.md .gitignore README.md AGENTS.md CLAUDE.md
```

## Naming

- Nim package/module: `UniText` (PascalCase).
- C library: `libUniText`. C header: `UniText.h`.
- C symbol prefix: the library's own name in lower case, `unitext_`. Not a
  short token: a binary that links several engines at once holds them all in
  one namespace.

## Conventions

- English comments, terse, describe what is done. No "deprecated".
- Parsing is bounded, and every bound is named: `ParseLimits` has four fields
  and all four must be positive. A partly-built one is refused rather than
  applied as a zero.
- A construct a target format cannot carry is **reported**, never dropped in
  silence. `codecInfo` states what each codec handles, and the conversion path
  reads it rather than assuming.
- The C ABI never raises: a failure is a NULL return with a code in
  `unitext_status` and a message in `unitext_last_error`. Every returned string
  is the caller's, released once with `unitext_cleanup`.
- Layers, checked by `build/unigate checkVGraph`: `model` up to `c_api`, never upward.
  Every name in `vgraph.cfg` answers to a real module -- one that does not
  constrains nothing, and the check then passes on a graph it never read.

## CI gates

Every task runs through `tools/gate.nim`: nimble exits 0 on a task whose `exec`
failed, so its exit code proves nothing and the task's own success marker is
what the gate reads.

- `testCi` + `testCiRelease` on ubuntu/macOS/Windows.
- `ctest`, `cexample` and `clib` on ubuntu/macOS/Windows.
- the Python matrix on ubuntu/macOS/Windows, 3.10 to 3.14.
- `lint`, `checkVGraph`, `docs` and `coverage` on ubuntu.
- `canary`, which must fail.
- `all-green` over all of them: the one check branch protection requires.

## Opt-in tasks

`fuzz`, `fuzzSmoke` and the two coverage-guided ones walk mutation corpora;
`differential` compares the pinned official corpus against an independent
converter; `sbom` builds the source SPDX document. None runs in the standard
CI matrix: they need a corpus, another implementation, or a sanitizer build
this repo does not ask of every contributor.
