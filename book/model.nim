# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nb.title = "The model"

nbText: """
# The model

One tree, four formats. A document is a sequence of blocks, each holding
inline nodes, and every node carries the span of source it came from.

That span is what makes a conversion answerable: when a codec reports that it
could not carry something, it can say *where*.
"""

nbCode:
  import UniText

  const source = "# Title\n\nA paragraph with **strong** text.\n"
  let parsed = parseDocument(source, formatMarkdown)

  for blockNode in parsed.document.blocks:
    echo blockNode.kind, "  id=", blockNode.id.string,
      "  bytes ", blockNode.span.byteStart, "..", blockNode.span.byteEnd,
      "  line ", blockNode.span.lineStart

nbText: """
## Interchange

The tree serialises to JSON, and reads back from it. That is the format a
caller stores, or hands to another process, when they want the document rather
than one of its renderings.
"""

nbCode:
  let json = toInterchangeString(parsed.document, pretty = false)
  echo json[0 ..< 120], " …"

  let restored = fromInterchangeString(json)
  echo "blocks restored: ", restored.blocks.len
  echo "round trip equal: ", toInterchangeString(restored) == json

nbText: """
## Editing is not mutation

An edit returns a new document; the original is untouched. Every operation
carries an identifier, and a target that is not there raises rather than
succeeding quietly — so replaying an edit onto a document that already has it
is an error a caller sees, not a silent no-op.
"""

nbCode:
  let target = parsed.document.blocks[^1].id
  let outcome = parsed.document.removeBlock("drop-the-paragraph", target)
  echo "before:    ", parsed.document.blocks.len, " blocks"
  echo "after:     ", outcome.document.blocks.len, " blocks"
  echo "original:  ", parsed.document.blocks.len, " blocks, untouched"

  # The same operation again, on the document that already has it applied.
  try:
    discard outcome.document.removeBlock("drop-the-paragraph", target)
  except EditError as error:
    echo "reapplied: ", error.msg

nbSave
