## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/strutils
import UniText/[codec, detect, model]
import UniText/codecs/shared

const RestructuredTextCodec* = CodecInfo(format: formatRestructuredText,
  name: "reStructuredText subset", capabilities: {capabilityParse,
      capabilitySerialize},
  supportedBlocks: {blockHeading, blockParagraph, blockUnorderedList,
      blockCode},
  supportedInlines: {inlineText, inlineEmphasis, inlineStrong, inlineCode, inlineLink})

proc parseRestructuredText*(content: string;
    limits = DefaultParseLimits): ParseResult =
  if content.len > limits.maxInputBytes:
    raise newException(CodecError, "input byte limit exceeded")
  let lines = content.sourceLines
  var blocks: seq[BlockNode]
  var index = 0
  var serial = 0
  proc identifier(kind: string): string =
    inc serial
    kind & "-" & $serial
  while index < lines.len:
    if lines[index].text.strip.len == 0:
      inc index
      continue
    if index + 1 < lines.len and lines[index + 1].text.len >=
        lines[index].text.len and lines[index + 1].text.len > 2 and
        lines[index + 1].text.allCharsInSet({'=', '-', '~', '^'}):
      let level = case lines[index + 1].text[0]
        of '=': 1
        of '-': 2
        of '~': 3
        else: 4
      let id = identifier("heading")
      let value = lines[index].text.strip
      let offset = lines[index].text.find(value)
      blocks.add(heading(id, level,
        parseInline(value, id, dialectRestructuredText,
          lines[index].sourceSpan(offset, offset + value.len)),
        lines.sourceSpan(index, index + 1)))
      index += 2
      continue
    if lines[index].text.startsWith("* "):
      let listId = identifier("list")
      let listStart = index
      var items: seq[BlockNode]
      while index < lines.len and lines[index].text.startsWith("* "):
        let itemId = identifier("item")
        items.add(paragraph(itemId,
          parseInline(lines[index].text[2 .. ^1], itemId,
            dialectRestructuredText, lines[index].sourceSpan(2)),
          lines[index].sourceSpan))
        inc index
      blocks.add(unorderedList(listId, items,
        lines.sourceSpan(listStart, index - 1)))
      continue
    if lines[index].text.startsWith(".. code-block::"):
      let sourceStart = index
      let language = lines[index].text[".. code-block::".len .. ^1].strip
      inc index
      while index < lines.len and lines[index].text.strip.len == 0: inc index
      var codeLines: seq[string]
      while index < lines.len and (lines[index].text.startsWith("   ") or
          lines[index].text.strip.len == 0):
        codeLines.add(if lines[index].text.len >= 3:
          lines[index].text[3 .. ^1] else: "")
        inc index
      blocks.add(codeBlock(identifier("code"),
        codeLines.join("\n").strip(leading = false), language,
        lines.sourceSpan(sourceStart, max(sourceStart, index - 1))))
      continue
    let paragraphStart = index
    while index < lines.len and lines[index].text.strip.len > 0:
      inc index
    let id = identifier("paragraph")
    blocks.add(paragraph(id, parseParagraphLines(lines, paragraphStart,
      index - 1, id, dialectRestructuredText),
      lines.sourceSpan(paragraphStart, index - 1)))
  result.document = newDocument(blocks, span = sourceSpanFromBounds(content, 0,
    content.len))
  result.document.validate(limits)

proc serializeRestructuredText*(document: Document): SerializeResult =
  document.validate
  for node in document.blocks:
    case node.kind
    of blockHeading:
      let value = node.inlines.serializeInline(dialectRestructuredText,
        result.diagnostics)
      let marker = ["=", "-", "~", "^"][min(node.level, 4) - 1]
      result.content.add(value & "\n" & marker.repeat(
          node.inlines.plainText.len) &
        "\n\n")
    of blockParagraph:
      result.content.add(node.inlines.serializeInline(dialectRestructuredText,
        result.diagnostics) & "\n\n")
    of blockUnorderedList:
      for item in node.blocks:
        if item.kind == blockParagraph:
          result.content.add("* " & item.inlines.serializeInline(
              dialectRestructuredText, result.diagnostics) & "\n")
        else:
          result.content.add("* " & item.blockText.replace("\n", " ") & "\n")
          result.diagnostics.add(diagnostic(diagnosticWarning,
            "rst.list-item-loss",
            "A non-paragraph list item was flattened to text.", $item.id))
      result.content.add("\n")
    of blockCode:
      var language = node.language
      if '\n' in language or '\r' in language:
        language.setLen(0)
        result.diagnostics.add(diagnostic(diagnosticWarning,
          "rst.code-language-loss",
          "The code language contains characters that cannot be emitted safely.",
          $node.id))
      result.content.add(".. code-block:: " & language & "\n\n")
      for line in node.code.splitLines: result.content.add("   " & line & "\n")
      result.content.add("\n")
    else:
      result.diagnostics.add(diagnostic(diagnosticWarning,
        "rst.block-unsupported",
        "The block cannot be serialized by the reStructuredText subset.", $node.id))
