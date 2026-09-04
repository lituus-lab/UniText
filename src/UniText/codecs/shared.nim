## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/[strutils]
import UniText/[codec, model]

type
  InlineDialect* = enum
    dialectMarkdown
    dialectRestructuredText
    dialectAsciiDoc

  SourceLine* = object
    text*: string
    byteStart*: int
    byteEnd*: int
    fullEnd*: int
    number*: int

proc parseInline*(value, baseId: string; dialect: InlineDialect;
    span = unknownSourceSpan()): seq[InlineNode]

proc sourceLines*(content: string): seq[SourceLine] =
  var start = 0
  var number = 1
  while start < content.len:
    var past = start
    while past < content.len and content[past] notin {'\r', '\n'}:
      inc past
    var fullPast = past
    if fullPast < content.len:
      if content[fullPast] == '\r' and fullPast + 1 < content.len and
          content[fullPast + 1] == '\n':
        fullPast += 2
      else:
        inc fullPast
    result.add(SourceLine(text: content[start ..< past], byteStart: start,
      byteEnd: past, fullEnd: fullPast, number: number))
    start = fullPast
    inc number

proc sourceSpan*(line: SourceLine; first = 0; past = -1): SourceSpan =
  let resolvedPast = if past < 0: line.text.len else: past
  if first < 0 or resolvedPast < first or resolvedPast > line.text.len:
    raise newException(CodecError, "line source span is invalid")
  model.sourceSpan(line.byteStart + first, line.byteStart + resolvedPast,
    line.number, first + 1, line.number, resolvedPast + 1)

proc sourceSpan*(lines: seq[SourceLine]; first, last: int): SourceSpan =
  if first < 0 or last < first or last >= lines.len:
    raise newException(CodecError, "source line range is invalid")
  model.sourceSpan(lines[first].byteStart, lines[last].byteEnd,
    lines[first].number, 1, lines[last].number, lines[last].text.len + 1)

proc parseParagraphLines*(lines: seq[SourceLine]; first, last: int;
    baseId: string; dialect: InlineDialect): seq[InlineNode] =
  if first < 0 or last < first or last >= lines.len:
    raise newException(CodecError, "paragraph source line range is invalid")
  var softBreakSerial = 0
  for index in first..last:
    let value = lines[index].text.strip
    if value.len > 0:
      let offset = lines[index].text.find(value)
      let lineId = if index == first: baseId else:
        baseId & "-line-" & $(index - first + 1)
      result.add(parseInline(value, lineId, dialect,
        lines[index].sourceSpan(offset, offset + value.len)))
    if index < last:
      inc softBreakSerial
      result.add(softBreakNode(baseId & "-soft-break-" & $softBreakSerial,
        model.sourceSpan(lines[index].byteEnd, lines[index + 1].byteStart,
          lines[index].number, lines[index].text.len + 1,
          lines[index + 1].number, 1)))

proc plainText*(nodes: seq[InlineNode]): string =
  for node in nodes:
    case node.kind
    of inlineText, inlineCode: result.add(node.text)
    of inlineSoftBreak: result.add(' ')
    of inlineHardBreak: result.add('\n')
    of inlineExtension: result.add(node.rawInline)
    else: result.add(node.children.plainText)

proc blockText*(node: BlockNode): string =
  case node.kind
  of blockCode: node.code
  of blockExtension: node.rawBlock
  else: node.inlines.plainText

proc isEscapable(dialect: InlineDialect; value: char): bool =
  case dialect
  of dialectMarkdown:
    value in "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
  of dialectRestructuredText:
    value in "\\`*_|"
  of dialectAsciiDoc:
    value in "\\*_`[]#="

proc escapeText(value: string; dialect: InlineDialect): string =
  for item in value:
    if dialect.isEscapable(item):
      result.add('\\')
    result.add(item)

proc unescapeText(value: string; dialect: InlineDialect): string =
  var index = 0
  while index < value.len:
    if value[index] == '\\' and index + 1 < value.len and
        dialect.isEscapable(value[index + 1]):
      result.add(value[index + 1])
      index += 2
    else:
      result.add(value[index])
      inc index

proc markerRun(value: string; start, past: int; marker: char): int =
  var index = start
  while index < past and value[index] == marker:
    inc result
    inc index

proc maximumRun(value: string; marker: char): int =
  var index = 0
  while index < value.len:
    if value[index] == marker:
      let length = value.markerRun(index, value.len, marker)
      result = max(result, length)
      index += length
    else:
      inc index

proc findUnescaped(value, marker: string; start, past: int;
    dialect: InlineDialect): int =
  var index = start
  while index + marker.len <= past:
    if value[index] == '\\' and index + 1 < past and
        dialect.isEscapable(value[index + 1]):
      index += 2
    elif value.continuesWith(marker, index):
      return index
    else:
      inc index
  -1

proc parseInline*(value, baseId: string; dialect: InlineDialect;
    span: SourceSpan): seq[InlineNode] =
  ## Parses the deliberately small portable inline intersection. Unsupported or
  ## malformed markup remains text, so parsing never deletes source content.
  var serial = 0
  if span.isKnown and (span.lineStart != span.lineEnd or
      span.byteEnd - span.byteStart != value.len):
    raise newException(CodecError,
      "inline source span must cover exactly one source line")

  proc rangeSpan(first, past: int): SourceSpan =
    if not span.isKnown:
      return unknownSourceSpan()
    sourceSpan(span.byteStart + first, span.byteStart + past, span.lineStart,
      span.columnStart + first, span.lineStart, span.columnStart + past)

  proc identifier(kind: string): NodeId =
    inc serial
    if serial == 1 and kind == "text":
      (baseId & "-text").nodeId
    else:
      (baseId & "-" & kind & "-" & $serial).nodeId

  proc parseRange(first, past: int): seq[InlineNode] =
    var index = first
    var text: string
    var textFirst = -1
    var textPast = -1
    template flushText() =
      if text.len > 0:
        result.add(textNode($identifier("text"), text,
          rangeSpan(textFirst, textPast)))
        text.setLen(0)
        textFirst = -1
        textPast = -1

    while index < past:
      if value[index] == '\\' and index + 1 < past and
          dialect.isEscapable(value[index + 1]):
        if textFirst < 0:
          textFirst = index
        text.add(value[index + 1])
        index += 2
        textPast = index
        continue

      var marker = ""
      var closing = ""
      var kind = inlineText
      case dialect
      of dialectMarkdown:
        if value.continuesWith("**", index):
          marker = "**"; closing = "**"; kind = inlineStrong
        elif value[index] == '*':
          marker = "*"; closing = "*"; kind = inlineEmphasis
        elif value[index] == '`':
          marker = "`".repeat(value.markerRun(index, past, '`'))
          closing = marker
          kind = inlineCode
      of dialectRestructuredText:
        if value.continuesWith("**", index):
          marker = "**"; closing = "**"; kind = inlineStrong
        elif value.continuesWith("``", index):
          marker = "`".repeat(value.markerRun(index, past, '`'))
          closing = marker
          kind = inlineCode
        elif value[index] == '*':
          marker = "*"; closing = "*"; kind = inlineEmphasis
      of dialectAsciiDoc:
        if value[index] == '*':
          marker = "*"; closing = "*"; kind = inlineStrong
        elif value[index] == '_':
          marker = "_"; closing = "_"; kind = inlineEmphasis
        elif value[index] == '`':
          marker = "`".repeat(value.markerRun(index, past, '`'))
          closing = marker
          kind = inlineCode

      if dialect == dialectMarkdown and value[index] == '[':
        let labelEnd = value.findUnescaped("]", index + 1, past, dialect)
        if labelEnd >= 0 and labelEnd + 1 < past and value[labelEnd + 1] == '(':
          let destinationEnd = value.findUnescaped(")", labelEnd + 2, past,
              dialect)
          if destinationEnd >= 0 and destinationEnd < past:
            flushText()
            result.add(linkNode($identifier("link"),
              value[labelEnd + 2 ..< destinationEnd].unescapeText(dialect),
              parseRange(index + 1, labelEnd), "",
              rangeSpan(index, destinationEnd + 1)))
            index = destinationEnd + 1
            continue

      if dialect == dialectRestructuredText and value[index] == '`' and
          (index + 1 >= past or value[index + 1] != '`'):
        let labelEnd = value.find(" <", index + 1)
        if labelEnd >= 0:
          let destinationEnd = value.find(">`_", labelEnd + 2)
          if destinationEnd >= 0 and destinationEnd < past:
            flushText()
            result.add(linkNode($identifier("link"),
              value[labelEnd + 2 ..< destinationEnd].unescapeText(dialect),
              parseRange(index + 1, labelEnd), "",
              rangeSpan(index, destinationEnd + 3)))
            index = destinationEnd + 3
            continue

      if dialect == dialectAsciiDoc and value.continuesWith("http", index):
        let labelStart = value.find('[', index + 4)
        if labelStart >= 0:
          let labelEnd = value.find(']', labelStart + 1)
          if labelEnd >= 0 and labelEnd < past and ' ' notin value[index ..< labelStart]:
            flushText()
            result.add(linkNode($identifier("link"),
              value[index ..< labelStart].unescapeText(dialect),
              parseRange(labelStart + 1, labelEnd), "",
              rangeSpan(index, labelEnd + 1)))
            index = labelEnd + 1
            continue

      if marker.len > 0:
        let closingAt = value.findUnescaped(closing, index + marker.len, past,
            dialect)
        if closingAt >= 0 and closingAt < past:
          flushText()
          if kind == inlineCode:
            result.add(codeNode($identifier("code"),
              value[index + marker.len ..< closingAt],
              rangeSpan(index, closingAt + closing.len)))
          else:
            let id = $identifier(if kind == inlineStrong: "strong" else:
              "emphasis")
            let children = parseRange(index + marker.len, closingAt)
            if children.len == 0:
              result.add(textNode(id & "-literal",
                value[index ..< closingAt + closing.len],
                rangeSpan(index, closingAt + closing.len)))
            elif kind == inlineStrong:
              result.add(strongNode(id, children,
                rangeSpan(index, closingAt + closing.len)))
            else:
              result.add(emphasisNode(id, children,
                rangeSpan(index, closingAt + closing.len)))
          index = closingAt + closing.len
          continue
      if textFirst < 0:
        textFirst = index
      text.add(value[index])
      inc index
      textPast = index
    flushText()

  result = parseRange(0, value.len)

proc dialectName(dialect: InlineDialect): string =
  case dialect
  of dialectMarkdown: "markdown"
  of dialectRestructuredText: "rst"
  of dialectAsciiDoc: "asciidoc"

proc serializeInline*(nodes: seq[InlineNode]; dialect: InlineDialect;
    diagnostics: var seq[Diagnostic]): string =
  for node in nodes:
    let children = node.children.serializeInline(dialect, diagnostics)
    case node.kind
    of inlineText: result.add(node.text.escapeText(dialect))
    of inlineCode:
      let minimum = if dialect == dialectRestructuredText: 2 else: 1
      let marker = "`".repeat(max(minimum, node.text.maximumRun('`') + 1))
      result.add(marker & node.text & marker)
    of inlineStrong:
      let marker = if dialect == dialectAsciiDoc: "*" else: "**"
      result.add(marker & children & marker)
    of inlineEmphasis:
      let marker = if dialect == dialectAsciiDoc: "_" else: "*"
      result.add(marker & children & marker)
    of inlineLink:
      if node.title.len > 0:
        diagnostics.add(diagnostic(diagnosticWarning,
          dialect.dialectName & ".link-title-loss",
          "The target subset cannot preserve the hyperlink title.", $node.id))
      case dialect
      of dialectMarkdown:
        var destination: string
        for item in node.destination:
          if item in {'\\', '(', ')'}: destination.add('\\')
          destination.add(item)
        result.add("[" & children & "](" & destination & ")")
      of dialectRestructuredText:
        result.add("`" & children & " <" & node.destination.escapeText(
          dialect) & ">`_")
      of dialectAsciiDoc:
        result.add(node.destination.escapeText(dialect) & "[" & children & "]")
    of inlineSoftBreak:
      result.add(' ')
      diagnostics.add(diagnostic(diagnosticWarning,
        dialect.dialectName & ".soft-break-loss",
        "The target subset normalizes a soft break to a space.", $node.id))
    of inlineHardBreak:
      result.add('\n')
      diagnostics.add(diagnostic(diagnosticWarning,
        dialect.dialectName & ".hard-break-loss",
        "The target subset cannot preserve hard-break semantics.", $node.id))
    of inlineExtension:
      result.add(node.rawInline.escapeText(dialect))
      diagnostics.add(diagnostic(diagnosticWarning,
        dialect.dialectName & ".extension-loss",
        "The format extension is emitted as literal text.", $node.id))

proc serializeInline*(nodes: seq[InlineNode]; dialect: InlineDialect): string =
  var ignoredDiagnostics: seq[Diagnostic]
  nodes.serializeInline(dialect, ignoredDiagnostics)
