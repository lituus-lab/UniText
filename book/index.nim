# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nb.title = "UniText"

nbText: """
# UniText

Structured documents, converted through one semantic model. Markdown,
reStructuredText, AsciiDoc and RTF go in; the same four come out; and in
between there is a single document tree that none of them owns.

The rule is **bounded, and honest about what it cannot carry**. Parsing has
limits it will not exceed, and a construct a target format cannot express is
*reported* rather than dropped in silence — which is the failure mode that
makes document converters untrustworthy.

Three surfaces, one engine: **Nim**, a **C ABI**, and a **Python** binding.

**Read this front to back.** Each chapter uses what the one before introduced.

## Installing

```bash
nimble install https://github.com/lituus-lab/UniText    # Nim
pip install lituus-unitext                              # Python
```

For C, the build produces `libUniText.a` and `include/UniText.h`:

```bash
build/unigate clibStatic
cc -Iinclude your.c libUniText.a
```

## What runs here

Every Nim block on these pages is compiled and run when the book is built, and
the output shown is what the code produced. A change that breaks the API breaks
the docs build — so prose that outlived its API cannot ship.

That guarantee covers `nbCode` blocks and nothing else. A fenced block written
inside prose is a picture of code, not code.

## A conversion, end to end
"""

nbCode:
  import UniText

  const source = "# Portable document\n\n" &
    "Text with **strong meaning**, `code`, and a [link](https://example.org).\n"

  let detected = detectFormat(source)
  echo "detected: ", detected.format, "  confidence: ", detected.confidence

  let converted = convertDocument(source, formatMarkdown,
    formatRestructuredText)
  echo "--- reStructuredText ---"
  echo converted.content

nbText: """
Nothing was guessed twice. `detectFormat` answers with a confidence rather than
a verdict, because a short document often *is* ambiguous — and a caller who
already knows the format passes it instead of asking.

## Supported versions

Nim 2.2 or later, on Linux, macOS and Windows. CPython 3.10 to 3.14, on the
same three. The `0.x` C ABI is not frozen.

## Licence, and where to ask

Apache-2.0. Contributions take a DCO sign-off; see `CONTRIBUTING.md`, and
`CODE_OF_CONDUCT.md` for conduct. Questions and defects go to the repository's
issue tracker.
"""

nbSave
