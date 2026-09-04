## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/strutils
import UniText/[codec, detect, model]
import UniText/codecs/shared

const AsciiDocCodec* = CodecInfo(format: formatAsciiDoc,
  name: "AsciiDoc subset",
  capabilities: {capabilityParse, capabilitySerialize},
  supportedBlocks: {blockHeading, blockParagraph, blockUnorderedList,
      blockCode},
  supportedInlines: {inlineText, inlineEmphasis, inlineStrong, inlineCode, inlineLink})

proc sourceDelimiter(line: string): int =
  if line.len >= 4 and line.allCharsInSet({'-'}): line.len else: 0

proc maximumSourceDelimiter(value: string): int =
  for line in value.splitLines:
    result = max(result, line.sourceDelimiter)

proc parseAsciiDoc*(content: string; limits = DefaultParseLimits): ParseResult =
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
    var headingLevel = 0
    while headingLevel < lines[index].text.len and
        lines[index].text[headingLevel] == '=':
      inc headingLevel
    if headingLevel in 1..6 and headingLevel < lines[index].text.len and
        lines[index].text[headingLevel] == ' ':
      let id = identifier("heading")
      let value = lines[index].text[headingLevel + 1 .. ^1]
      blocks.add(heading(id, headingLevel,
        parseInline(value, id, dialectAsciiDoc,
          lines[index].sourceSpan(headingLevel + 1)), lines[index].sourceSpan))
      inc index
      continue
    if lines[index].text.startsWith("* "):
      let listId = identifier("list")
      let listStart = index
      var items: seq[BlockNode]
      while index < lines.len and lines[index].text.startsWith("* "):
        let itemId = identifier("item")
        let value = lines[index].text[2 .. ^1]
        items.add(paragraph(itemId, parseInline(value, itemId,
          dialectAsciiDoc, lines[index].sourceSpan(2)),
          lines[index].sourceSpan))
        inc index
      blocks.add(unorderedList(listId, items,
        lines.sourceSpan(listStart, index - 1)))
      continue
    if lines[index].text.startsWith("[source,") and
        lines[index].text.endsWith("]"):
      let sourceStart = index
      let language = lines[index].text[8 .. ^2]
      inc index
      if index >= lines.len or lines[index].text.sourceDelimiter == 0:
        raise newException(CodecError, "AsciiDoc source block delimiter is missing")
      let delimiter = lines[index].text
      inc index
      var codeLines: seq[string]
      while index < lines.len and lines[index].text != delimiter:
        codeLines.add(lines[index].text)
        inc index
      if index >= lines.len: raise newException(CodecError, "unterminated AsciiDoc source block")
      let sourceEnd = index
      inc index
      blocks.add(codeBlock(identifier("code"), codeLines.join("\n"),
        language, lines.sourceSpan(sourceStart, sourceEnd)))
      continue
    let paragraphStart = index
    while index < lines.len and lines[index].text.strip.len > 0:
      inc index
    let id = identifier("paragraph")
    blocks.add(paragraph(id, parseParagraphLines(lines, paragraphStart,
      index - 1, id, dialectAsciiDoc),
      lines.sourceSpan(paragraphStart, index - 1)))
  result.document = newDocument(blocks, span = sourceSpanFromBounds(content, 0,
    content.len))
  result.document.validate(limits)

proc serializeAsciiDoc*(document: Document): SerializeResult =
  document.validate
  for node in document.blocks:
    case node.kind
    of blockHeading:
      result.content.add("=".repeat(node.level) & " " &
        node.inlines.serializeInline(dialectAsciiDoc, result.diagnostics) &
        "\n\n")
    of blockParagraph:
      result.content.add(node.inlines.serializeInline(dialectAsciiDoc,
        result.diagnostics) & "\n\n")
    of blockUnorderedList:
      for item in node.blocks:
        if item.kind == blockParagraph:
          result.content.add("* " & item.inlines.serializeInline(
              dialectAsciiDoc, result.diagnostics) & "\n")
        else:
          result.content.add("* " & item.blockText.replace("\n", " ") & "\n")
          result.diagnostics.add(diagnostic(diagnosticWarning,
            "asciidoc.list-item-loss",
            "A non-paragraph list item was flattened to text.", $item.id))
      result.content.add("\n")
    of blockCode:
      let delimiter = "-".repeat(max(4, node.code.maximumSourceDelimiter + 1))
      var language = node.language
      if '\n' in language or '\r' in language or ']' in language:
        language.setLen(0)
        result.diagnostics.add(diagnostic(diagnosticWarning,
          "asciidoc.code-language-loss",
          "The code language contains characters that cannot be emitted safely.",
          $node.id))
      result.content.add("[source," & language & "]\n" & delimiter & "\n" &
        node.code & "\n" & delimiter & "\n\n")
    else:
      result.diagnostics.add(diagnostic(diagnosticWarning,
        "asciidoc.block-unsupported",
        "The block cannot be serialized by the AsciiDoc subset.", $node.id))
