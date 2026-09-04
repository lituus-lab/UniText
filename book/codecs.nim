# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nb.title = "Codecs"

nbText: """
# Codecs

Four formats, and none of them can express what the others can. A converter
that pretends otherwise loses things quietly; this one declares what each codec
carries, and reports what it had to leave behind.

## What a codec says about itself

`codecInfo` is not documentation, it is data: the blocks and inlines the codec
handles, which the conversion path reads rather than assumes.
"""

nbCode:
  import std/strutils
  import UniText

  for format in [formatMarkdown, formatRestructuredText, formatAsciiDoc,
      formatRtf]:
    let info = codecInfo(format)
    echo info.name
    echo "  inlines: ", info.supportedInlines

nbText: """
Read the last line again. The RTF subset carries `inlineText` and nothing else
— no emphasis, no code, no links. That is a property of this codec's subset,
and it is the reason the next section exists.

## Conversion reports what it cannot carry
"""

nbCode:
  const source = "# Title\n\nSome **strong** text, `code`, and a " &
    "[link](https://example.org).\n"

  let toRst = convertDocument(source, formatMarkdown, formatRestructuredText)
  echo "markdown -> reStructuredText: ", toRst.diagnostics.len, " diagnostics"

  let toRtf = convertDocument(source, formatMarkdown, formatRtf)
  echo "markdown -> RTF:             ", toRtf.diagnostics.len, " diagnostics"
  for diagnostic in toRtf.diagnostics:
    echo "  ", diagnostic.severity, "  ", diagnostic.code
    echo "    ", diagnostic.message

nbText: """
Two warnings, each naming the construct and the reason. Nothing was refused —
the RTF still came out, and it is the best RTF this subset can make of that
input. What changed is that the caller *knows*.

A conversion between two formats with the same coverage reports nothing, which
is the other half of the same contract: a diagnostic means something, because
it is not emitted routinely.

## The output itself
"""

nbCode:
  echo toRtf.content

nbText: """
## Bounded, not best-effort

Every parse takes limits — input bytes, nesting depth, node count — and exceeds
them by refusing rather than by allocating. A document format is an input from
somewhere else, and "somewhere else" is exactly where a decompression bomb
comes from.
"""

nbCode:
  let large = "paragraph\n\n".repeat(200)
  try:
    discard parseDocument(large, formatMarkdown,
      limits = ParseLimits(maxInputBytes: 64, maxNestingDepth: 8,
        maxNodes: 100, maxDecodedBytes: 1024))
  except CodecError as error:
    echo "refused: ", error.msg

nbText: """
Name every field. A `ParseLimits` left partly unset is a limit of zero on
whatever was omitted, and Nim leaves an int at zero without complaint —
so the limits themselves are checked before any document is:
"""

nbCode:
  try:
    discard parseDocument("text\n", formatMarkdown,
      limits = ParseLimits(maxInputBytes: 1024, maxNestingDepth: 8,
        maxNodes: 100)) # maxDecodedBytes omitted, so zero
  except ModelError as error:
    echo "refused: ", error.msg

nbSave
