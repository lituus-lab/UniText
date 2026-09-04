## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/[sequtils, sets, strutils, unicode]
import UniText/[codec, detect, model]
import UniText/codecs/shared

const RtfCodec* = CodecInfo(format: formatRtf, name: "RTF styled subset",
  capabilities: {capabilityParse, capabilitySerialize},
  supportedBlocks: {blockHeading, blockParagraph, blockUnorderedList,
      blockCode},
  supportedInlines: {inlineText})

proc isHexDigit(value: char): bool =
  value in {'0'..'9', 'a'..'f', 'A'..'F'}

proc skipGroup(content: string; start: int): int =
  var depth = 1
  var index = start + 1
  while index < content.len:
    if content[index] == '{':
      inc depth
      inc index
    elif content[index] == '}':
      dec depth
      if depth == 0: return index + 1
      inc index
    elif content[index] == '\\':
      if index + 1 >= content.len:
        raise newException(CodecError, "trailing RTF escape in group")
      if content[index + 1] in {'\\', '{', '}', '*', '~', '_', '-'}:
        index += 2
      elif content[index + 1] == '\'':
        if index + 3 >= content.len or not content[index + 2].isHexDigit or
            not content[index + 3].isHexDigit:
          raise newException(CodecError, "invalid RTF hexadecimal escape")
        index += 4
      else:
        inc index
        var word: string
        while index < content.len and content[index].isAlphaAscii:
          word.add(content[index])
          inc index
        var sign = 1
        if index < content.len and content[index] == '-':
          sign = -1
          inc index
        var numberText: string
        while index < content.len and content[index].isDigit:
          if numberText.len >= 10:
            raise newException(CodecError, "RTF control number is too large")
          numberText.add(content[index])
          inc index
        let number = if numberText.len == 0: 0 else:
          try: sign * parseInt(numberText)
          except ValueError:
            raise newException(CodecError, "invalid RTF control number")
        if index < content.len and content[index] == ' ': inc index
        if word == "bin":
          if number < 0 or number > content.len - index:
            raise newException(CodecError, "RTF binary payload exceeds its group")
          index += number
    else:
      inc index
  raise newException(CodecError, "unterminated RTF group")

proc addRtfUnicode(result: var string; unit: int) =
  let signed = if unit >= 0x8000: unit - 0x10000 else: unit
  result.add("\\u" & $signed & "?")

proc escapeRtf(value: string): string =
  for rune in value.runes:
    let codepoint = int(rune)
    if codepoint == int('\\'):
      result.add("\\\\")
    elif codepoint == int('{'):
      result.add("\\{")
    elif codepoint == int('}'):
      result.add("\\}")
    elif codepoint == int('\n'):
      result.add("\\line ")
    elif codepoint == int('\r'):
      discard
    elif codepoint == int('\t'):
      result.add("\\tab ")
    elif codepoint in 0x20..0x7e:
      result.add(char(codepoint))
    else:
      if codepoint <= 0xffff:
        result.addRtfUnicode(codepoint)
      else:
        let scalar = codepoint - 0x10000
        result.addRtfUnicode(0xd800 + (scalar shr 10))
        result.addRtfUnicode(0xdc00 + (scalar and 0x3ff))

proc ansiCodepoint(value: int): int =
  case value
  of 0x80: 0x20ac
  of 0x82: 0x201a
  of 0x83: 0x0192
  of 0x84: 0x201e
  of 0x85: 0x2026
  of 0x86: 0x2020
  of 0x87: 0x2021
  of 0x88: 0x02c6
  of 0x89: 0x2030
  of 0x8a: 0x0160
  of 0x8b: 0x2039
  of 0x8c: 0x0152
  of 0x8e: 0x017d
  of 0x91: 0x2018
  of 0x92: 0x2019
  of 0x93: 0x201c
  of 0x94: 0x201d
  of 0x95: 0x2022
  of 0x96: 0x2013
  of 0x97: 0x2014
  of 0x98: 0x02dc
  of 0x99: 0x2122
  of 0x9a: 0x0161
  of 0x9b: 0x203a
  of 0x9c: 0x0153
  of 0x9e: 0x017e
  of 0x9f: 0x0178
  else: value

proc serializeRtfInline(nodes: seq[InlineNode]; diagnostics: var seq[
    Diagnostic]): string =
  for node in nodes:
    case node.kind
    of inlineText: result.add(node.text.escapeRtf)
    of inlineStrong:
      result.add("\\b " & serializeRtfInline(node.children, diagnostics) & "\\b0 ")
    of inlineEmphasis:
      result.add("\\i " & serializeRtfInline(node.children, diagnostics) & "\\i0 ")
    of inlineCode:
      result.add(node.text.escapeRtf)
      diagnostics.add(diagnostic(diagnosticWarning, "rtf.inline-code-loss",
        "The RTF subset cannot preserve inline-code semantics.", $node.id))
    of inlineLink:
      result.add(node.children.plainText.escapeRtf)
      diagnostics.add(diagnostic(diagnosticWarning, "rtf.link-loss",
        "The RTF subset cannot preserve hyperlink destinations.", $node.id))
    of inlineSoftBreak: result.add(' ')
    of inlineHardBreak: result.add("\\line ")
    of inlineExtension:
      result.add(node.rawInline.escapeRtf)
      diagnostics.add(diagnostic(diagnosticWarning, "rtf.extension-loss",
        "A format extension was normalized while serializing RTF.", $node.id))

proc parseRtf*(content: string; limits = DefaultParseLimits): ParseResult =
  if content.len > limits.maxInputBytes:
    raise newException(CodecError, "input byte limit exceeded")
  if not content.startsWith("{\\rtf"):
    raise newException(CodecError, "RTF signature is missing")
  let sourceLocator = content.sourceIndex
  var blocks: seq[BlockNode]
  var diagnostics: seq[Diagnostic]
  var index = 0
  var style = 0
  var paragraphText: string
  var bullet = false
  var listItems: seq[tuple[value: string; span: SourceSpan]]
  var serial = 0
  var inlineNormalized = false
  var undefinedAnsiByte = false
  var unknownControls = initHashSet[string]()
  var groupDepth = 0
  var unicodeFallbackLength = 1
  var fallbackRemaining = 0
  var pendingHighSurrogate = -1
  var paragraphSourceStart = -1
  var paragraphSourceEnd = -1

  proc identifier(kind: string): string =
    inc serial
    kind & "-" & $serial

  proc appendCodepoint(codepoint: int) =
    paragraphText.add(Rune(codepoint).toUTF8)

  proc touchSource(first, past: int) =
    if paragraphSourceStart < 0:
      paragraphSourceStart = first
    paragraphSourceEnd = max(paragraphSourceEnd, past)

  proc flushPendingSurrogate() =
    if pendingHighSurrogate >= 0:
      appendCodepoint(0xfffd)
      pendingHighSurrogate = -1

  proc appendUtf16(unit: int) =
    if unit in 0xd800..0xdbff:
      flushPendingSurrogate()
      pendingHighSurrogate = unit
    elif unit in 0xdc00..0xdfff and pendingHighSurrogate >= 0:
      let codepoint = 0x10000 + ((pendingHighSurrogate - 0xd800) shl 10) +
        (unit - 0xdc00)
      pendingHighSurrogate = -1
      appendCodepoint(codepoint)
    else:
      flushPendingSurrogate()
      if unit in 0xdc00..0xdfff:
        appendCodepoint(0xfffd)
      else:
        appendCodepoint(unit)

  proc ignoredDestination(start: int): bool =
    for prefix in ["{\\*", "{\\fonttbl", "{\\stylesheet", "{\\colortbl",
        "{\\info", "{\\pict", "{\\object", "{\\filetbl", "{\\listtable",
        "{\\listoverridetable"]:
      if content.continuesWith(prefix, start): return true

  proc skipFallbackCharacter() =
    if index >= content.len: return
    if content[index] == '\\' and index + 1 < content.len:
      if content[index + 1] == '\'' and index + 3 < content.len:
        index += 4
      else:
        index += 2
    else:
      inc index

  proc flushList() =
    if listItems.len == 0: return
    let listId = identifier("list")
    var items: seq[BlockNode]
    for entry in listItems:
      let itemId = identifier("item")
      items.add(paragraph(itemId,
        @[textNode(itemId & "-text", entry.value.strip, entry.span)],
        entry.span))
    blocks.add(unorderedList(listId, items,
      model.sourceSpan(listItems[0].span.byteStart,
        listItems[^1].span.byteEnd, listItems[0].span.lineStart,
        listItems[0].span.columnStart, listItems[^1].span.lineEnd,
        listItems[^1].span.columnEnd)))
    listItems.setLen(0)

  proc flushParagraph() =
    flushPendingSurrogate()
    let value = paragraphText.strip
    paragraphText.setLen(0)
    let span = if paragraphSourceStart >= 0:
      sourceLocator.spanFor(paragraphSourceStart, paragraphSourceEnd)
    else:
      unknownSourceSpan()
    paragraphSourceStart = -1
    paragraphSourceEnd = -1
    if value.len == 0:
      bullet = false
      return
    if bullet:
      listItems.add((value, span))
      bullet = false
      return
    flushList()
    case style
    of 1:
      let id = identifier("heading")
      blocks.add(heading(id, 1, @[textNode(id & "-text", value, span)], span))
    of 2:
      blocks.add(codeBlock(identifier("code"), value, span = span))
    else:
      let id = identifier("paragraph")
      blocks.add(paragraph(id, @[textNode(id & "-text", value, span)], span))

  while index < content.len:
    if fallbackRemaining > 0:
      skipFallbackCharacter()
      dec fallbackRemaining
      continue
    if content[index] == '{':
      if ignoredDestination(index):
        index = content.skipGroup(index)
        continue
      inc groupDepth
      inc index
      continue
    if content[index] == '}':
      dec groupDepth
      if groupDepth < 0:
        raise newException(CodecError, "unbalanced RTF closing brace")
      inc index
      continue
    if content[index] == '\\':
      let controlStart = index
      if index + 1 >= content.len: raise newException(CodecError, "trailing RTF escape")
      if content[index + 1] in {'\\', '{', '}'}:
        flushPendingSurrogate()
        paragraphText.add(content[index + 1])
        index += 2
        touchSource(controlStart, index)
        continue
      if content[index + 1] == '\'':
        if index + 3 >= content.len or not content[index + 2].isHexDigit or
            not content[index + 3].isHexDigit:
          raise newException(CodecError, "invalid RTF hexadecimal escape")
        flushPendingSurrogate()
        let value = parseHexInt(content[index + 2 .. index + 3])
        let codepoint = value.ansiCodepoint
        if value in {0x81, 0x8d, 0x8f, 0x90, 0x9d}:
          undefinedAnsiByte = true
          appendCodepoint(0xfffd)
        else:
          appendCodepoint(codepoint)
        index += 4
        touchSource(controlStart, index)
        continue
      if content[index + 1] in {'~', '_', '-'}:
        flushPendingSurrogate()
        case content[index + 1]
        of '~': appendCodepoint(0x00a0)
        of '_': appendCodepoint(0x2011)
        else: discard
        index += 2
        touchSource(controlStart, index)
        continue
      inc index
      var word: string
      while index < content.len and content[index].isAlphaAscii:
        word.add(content[index])
        inc index
      var sign = 1
      if index < content.len and content[index] == '-':
        sign = -1
        inc index
      var numberText: string
      while index < content.len and content[index].isDigit:
        if numberText.len >= 10:
          raise newException(CodecError, "RTF control number is too large")
        numberText.add(content[index])
        inc index
      if index < content.len and content[index] == ' ': inc index
      let number = if numberText.len == 0: 0 else:
        try: sign * parseInt(numberText)
        except ValueError:
          raise newException(CodecError, "invalid RTF control number")
      case word
      of "par":
        touchSource(controlStart, index)
        flushParagraph()
      of "s":
        touchSource(controlStart, index)
        style = number
      of "bullet":
        touchSource(controlStart, index)
        bullet = true
      of "tab":
        touchSource(controlStart, index)
        paragraphText.add(' ')
      of "line":
        touchSource(controlStart, index)
        paragraphText.add('\n')
      of "b", "i":
        touchSource(controlStart, index)
        inlineNormalized = true
      of "u":
        touchSource(controlStart, index)
        if number notin -32768..65535:
          raise newException(CodecError, "RTF Unicode value is outside 16-bit range")
        appendUtf16(if number < 0: number + 0x10000 else: number)
        fallbackRemaining = unicodeFallbackLength
      of "uc":
        if number notin 0..16:
          raise newException(CodecError, "RTF Unicode fallback length is unsupported")
        unicodeFallbackLength = number
      of "bin":
        flushPendingSurrogate()
        if number < 0 or number > content.len - index:
          raise newException(CodecError, "RTF binary payload exceeds the document")
        index += number
      of "rtf", "ansi", "deff", "fs", "f", "lang", "pard": discard
      else:
        if word.len > 0: unknownControls.incl(word)
      continue
    if content[index] notin {'\r', '\n'}:
      let sourceStart = index
      flushPendingSurrogate()
      let value = ord(content[index])
      if value >= 0x80:
        let codepoint = value.ansiCodepoint
        if value in {0x81, 0x8d, 0x8f, 0x90, 0x9d}:
          undefinedAnsiByte = true
          appendCodepoint(0xfffd)
        else:
          appendCodepoint(codepoint)
      else:
        paragraphText.add(content[index])
      touchSource(sourceStart, index + 1)
    inc index
  if groupDepth != 0:
    raise newException(CodecError, "unterminated RTF document group")
  flushParagraph()
  flushList()
  if inlineNormalized:
    diagnostics.add(diagnostic(diagnosticWarning, "rtf.inline-normalized",
      "RTF inline formatting was normalized by the supported block-level codec subset."))
  if unknownControls.len > 0:
    diagnostics.add(diagnostic(diagnosticWarning, "rtf.controls-unsupported",
      "Unsupported RTF controls were ignored: " & unknownControls.toSeq.join(", ")))
  if undefinedAnsiByte:
    diagnostics.add(diagnostic(diagnosticWarning, "rtf.ansi-byte-undefined",
      "Undefined Windows-1252 bytes were replaced with U+FFFD."))
  let document = newDocument(blocks,
    span = sourceLocator.spanFor(0, content.len))
  document.validate(limits)
  result = ParseResult(document: document, diagnostics: diagnostics)

proc serializeRtf*(document: Document): SerializeResult =
  document.validate
  result.content = "{\\rtf1\\ansi\\uc1\\deff0\n{\\fonttbl{\\f0 Helvetica;}}\n" &
    "{\\stylesheet{\\s0 Normal;}{\\s1\\sbasedon0 Heading 1;}" &
    "{\\s2\\sbasedon0 Code;}}\n"
  for node in document.blocks:
    case node.kind
    of blockHeading:
      if node.level != 1:
        result.diagnostics.add(diagnostic(diagnosticWarning,
          "rtf.heading-level-loss",
          "The RTF subset serializes every heading with the Heading 1 style.", $node.id))
      result.content.add("\\s1\\b " & serializeRtfInline(node.inlines,
          result.diagnostics) & "\\b0\\par\n")
    of blockParagraph:
      result.content.add("\\s0 " & serializeRtfInline(node.inlines,
          result.diagnostics) &
        "\\par\n")
    of blockUnorderedList:
      for item in node.blocks:
        result.content.add("\\s0\\bullet\\tab " &
          serializeRtfInline(item.inlines, result.diagnostics) & "\\par\n")
    of blockCode:
      result.content.add("\\s2 " & node.code.escapeRtf & "\\par\n")
      if node.language.len > 0:
        result.diagnostics.add(diagnostic(diagnosticWarning,
          "rtf.code-language-loss",
          "The RTF subset cannot preserve the code language.", $node.id))
    else:
      result.diagnostics.add(diagnostic(diagnosticWarning,
        "rtf.block-unsupported",
        "The block cannot be serialized by the RTF subset.", $node.id))
  result.content.add("}\n")
