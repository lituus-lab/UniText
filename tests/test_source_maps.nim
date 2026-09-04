## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/[os, unittest]
import UniText

proc assertComplete(document: Document; content: string) =
  check document.span.isKnown
  check document.span.byteStart == 0
  check document.span.byteEnd == content.len

  proc visitInline(node: InlineNode; parent: SourceSpan) =
    check node.span.isKnown
    check parent.byteStart <= node.span.byteStart
    check node.span.byteEnd <= parent.byteEnd
    check node.span.lineStart >= parent.lineStart
    for child in node.children:
      visitInline(child, node.span)

  proc visitBlock(node: BlockNode; parent: SourceSpan) =
    check node.span.isKnown
    check parent.byteStart <= node.span.byteStart
    check node.span.byteEnd <= parent.byteEnd
    check node.span.lineStart >= parent.lineStart
    for inline in node.inlines:
      visitInline(inline, node.span)
    for child in node.blocks:
      visitBlock(child, node.span)

  for blockNode in document.blocks:
    visitBlock(blockNode, document.span)

suite "Complete source maps":
  test "maps exact Markdown syntax ranges with exclusive byte bounds":
    let content = "# Hé\n\nA **bold** value\n"
    let document = parseMarkdown(content).document
    document.assertComplete(content)
    check document.blocks[0].span.byteStart == 0
    check document.blocks[0].span.byteEnd == 5
    check document.blocks[0].inlines[0].span.byteStart == 2
    check document.blocks[0].inlines[0].span.byteEnd == 5
    check document.blocks[1].span.byteStart == 7
    check document.blocks[1].inlines[1].kind == inlineStrong
    check document.blocks[1].inlines[1].span.byteStart == 9
    check document.blocks[1].inlines[1].span.byteEnd == 17
    check document.blocks[1].inlines[1].children[0].span.byteStart == 11
    check document.blocks[1].inlines[1].children[0].span.byteEnd == 15

  test "maps every parsed node for all advertised codecs":
    let fixtureRoot = currentSourcePath.parentDir.parentDir / "fixtures" /
      "equivalent"
    for pair in [
      (fixtureRoot / "sample.md", formatMarkdown),
      (fixtureRoot / "sample.rst", formatRestructuredText),
      (fixtureRoot / "sample.adoc", formatAsciiDoc),
      (fixtureRoot / "sample.rtf", formatRtf),
    ]:
      let content = readFile(pair[0])
      let document = parseDocument(content, pair[1]).document
      document.assertComplete(content)

  test "preserves CRLF byte and line coordinates":
    let document = parseMarkdown("# Title\r\n\r\nBody\r\n").document
    check document.blocks[0].span.byteStart == 0
    check document.blocks[0].span.byteEnd == 7
    check document.blocks[0].span.lineStart == 1
    check document.blocks[1].span.byteStart == 11
    check document.blocks[1].span.lineStart == 3
    check document.blocks[1].inlines[0].span.columnStart == 1

  test "marks synthetic and replaced content as generated":
    let synthetic = newDocument(@[
      paragraph("paragraph", @[textNode("text", "value")])
    ])
    check not synthetic.span.isKnown
    check not synthetic.blocks[0].span.isKnown
    let source = parseMarkdown("# Title").document
    let edited = source.applyEdit(EditOperation(operationId: "replace",
      target: "heading-1-text".nodeId, kind: editReplaceText,
      value: "Changed"))
    check source.blocks[0].inlines[0].span.isKnown
    check not edited.document.blocks[0].inlines[0].span.isKnown

