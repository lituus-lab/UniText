## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/[strutils]
import UniText/[codec, detect, model]
import UniText/codecs/shared

const MarkdownCodec* = CodecInfo(format: formatMarkdown,
  name: "Markdown subset",
  capabilities: {capabilityParse, capabilitySerialize},
  supportedBlocks: {blockHeading, blockParagraph, blockUnorderedList,
      blockCode},
  supportedInlines: {inlineText, inlineEmphasis, inlineStrong, inlineCode, inlineLink})

proc fenceRun(line: string): int =
  while result < line.len and line[result] == '`':
    inc result

proc openingFenceRun(line: string): int =
  result = line.fenceRun
  if result < 3 or '`' in line[result .. ^1]:
    result = 0

proc closesFence(line: string; minimum: int): bool =
  let run = line.fenceRun
  run >= minimum and line[run .. ^1].strip.len == 0

proc maximumFenceRun(value: string): int =
  var run = 0
  for item in value:
    if item == '`':
      inc run
      result = max(result, run)
    else:
      run = 0

proc parseMarkdown*(content: string; limits = DefaultParseLimits): ParseResult =
  if content.len > limits.maxInputBytes:
    raise newException(CodecError, "input byte limit exceeded")
  let lines = content.sourceLines
  var blocks: seq[BlockNode]
  var index = 0
  var serial = 0

  proc headingLevel(line: string): int =
    while result < line.len and line[result] == '#': inc result
    if result notin 1..6 or result >= line.len or line[result] != ' ':
      result = 0

  proc identifier(kind: string): string =
    inc serial
    kind & "-" & $serial

  proc startsBlock(line: string): bool =
    line.strip.len == 0 or headingLevel(line) > 0 or line.startsWith("- ") or
      line.openingFenceRun > 0

  while index < lines.len:
    let line = lines[index].text
    if line.strip.len == 0:
      inc index
      continue
    let openingFence = line.openingFenceRun
    if openingFence >= 3:
      let sourceStart = index
      let language = line[openingFence .. ^1].strip
      var codeLines: seq[string]
      inc index
      while index < lines.len and not lines[index].text.closesFence(openingFence):
        codeLines.add(lines[index].text)
        inc index
      if index >= lines.len:
        raise newException(CodecError, "unterminated Markdown code fence")
      let sourceEnd = index
      blocks.add(codeBlock(identifier("code"), codeLines.join("\n"), language,
        lines.sourceSpan(sourceStart, sourceEnd)))
      inc index
      continue
    let level = headingLevel(line)
    if level > 0:
      let id = identifier("heading")
      blocks.add(heading(id, level,
        parseInline(line[level + 1 .. ^1], id, dialectMarkdown,
          lines[index].sourceSpan(level + 1)), lines[index].sourceSpan))
      inc index
      continue
    if line.startsWith("- "):
      let listId = identifier("list")
      let listStart = index
      var items: seq[BlockNode]
      while index < lines.len and lines[index].text.startsWith("- "):
        let itemId = identifier("item")
        items.add(paragraph(itemId,
          parseInline(lines[index].text[2 .. ^1], itemId, dialectMarkdown,
            lines[index].sourceSpan(2)), lines[index].sourceSpan))
        inc index
      blocks.add(unorderedList(listId, items,
        lines.sourceSpan(listStart, index - 1)))
      continue
    let paragraphStart = index
    while index < lines.len and not lines[index].text.startsBlock:
      inc index
    let id = identifier("paragraph")
    blocks.add(paragraph(id, parseParagraphLines(lines, paragraphStart,
      index - 1, id, dialectMarkdown),
      lines.sourceSpan(paragraphStart, index - 1)))
  result.document = newDocument(blocks, span = sourceSpanFromBounds(content, 0,
    content.len))
  result.document.validate(limits)

proc serializeMarkdown*(document: Document): SerializeResult =
  document.validate
  for node in document.blocks:
    case node.kind
    of blockHeading:
      result.content.add("#".repeat(node.level) & " " &
        node.inlines.serializeInline(dialectMarkdown, result.diagnostics) &
        "\n\n")
    of blockParagraph:
      result.content.add(node.inlines.serializeInline(dialectMarkdown,
        result.diagnostics) & "\n\n")
    of blockUnorderedList:
      for item in node.blocks:
        if item.kind == blockParagraph:
          result.content.add("- " & item.inlines.serializeInline(
              dialectMarkdown, result.diagnostics) & "\n")
        else:
          result.content.add("- " & item.blockText.replace("\n", " ") & "\n")
          result.diagnostics.add(diagnostic(diagnosticWarning,
            "markdown.list-item-loss",
            "A non-paragraph list item was flattened to text.", $item.id))
      result.content.add("\n")
    of blockCode:
      let fence = "`".repeat(max(3, node.code.maximumFenceRun + 1))
      var language = node.language
      if '\n' in language or '\r' in language or '`' in language:
        language.setLen(0)
        result.diagnostics.add(diagnostic(diagnosticWarning,
          "markdown.code-language-loss",
          "The code language contains characters that cannot be emitted safely.",
          $node.id))
      result.content.add(fence & language & "\n" & node.code & "\n" & fence &
        "\n\n")
    else:
      result.diagnostics.add(diagnostic(diagnosticWarning,
        "markdown.block-unsupported",
        "The block cannot be serialized by the Markdown subset.", $node.id))
