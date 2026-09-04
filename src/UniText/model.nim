## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/[sets, tables]

type
  NodeId* = distinct string

  InlineKind* = enum
    inlineText
    inlineEmphasis
    inlineStrong
    inlineCode
    inlineLink
    inlineSoftBreak
    inlineHardBreak
    inlineExtension

  BlockKind* = enum
    blockHeading
    blockParagraph
    blockOrderedList
    blockUnorderedList
    blockQuote
    blockCode
    blockThematicBreak
    blockExtension

  SourceSpan* = object
    knownField: bool
    byteStartField: int
    byteEndField: int
    lineStartField: int
    columnStartField: int
    lineEndField: int
    columnEndField: int

  SourceIndex* = object
    lineStartsField: seq[int]
    crlfMiddlesField: seq[int]
    contentLengthField: int

  InlineNode* = ref object
    idField: NodeId
    kindField: InlineKind
    childrenField: seq[InlineNode]
    spanField: SourceSpan
    textField: string
    destinationField: string
    titleField: string
    formatNameField: string
    rawInlineField: string

  BlockNode* = ref object
    idField: NodeId
    kindField: BlockKind
    blocksField: seq[BlockNode]
    inlinesField: seq[InlineNode]
    spanField: SourceSpan
    levelField: int
    startField: int
    languageField: string
    codeField: string
    formatNameField: string
    rawBlockField: string

  Document* = object
    metadataField: OrderedTable[string, string]
    blocksField: seq[BlockNode]
    spanField: SourceSpan

  DiagnosticSeverity* = enum
    diagnosticInfo
    diagnosticWarning
    diagnosticError

  Diagnostic* = object
    severity*: DiagnosticSeverity
    code*: string
    message*: string
    nodeId*: NodeId
    span*: SourceSpan

  ParseLimits* = object
    maxInputBytes*: int
    maxNestingDepth*: int
    maxNodes*: int
    maxDecodedBytes*: int

  ModelError* = object of ValueError

const DefaultParseLimits* = ParseLimits(maxInputBytes: 16 * 1024 * 1024,
  maxNestingDepth: 64, maxNodes: 1_000_000, maxDecodedBytes: 64 * 1024 * 1024)

proc isValidUtf8*(value: string): bool =
  ## Strict Unicode-scalar UTF-8 validation: rejects overlong sequences,
  ## surrogate code points, truncated sequences, and values above U+10FFFF.
  var index = 0
  template continuation(position: int): bool =
    position < value.len and ord(value[position]) in 0x80..0xbf
  while index < value.len:
    let first = ord(value[index])
    if first <= 0x7f:
      inc index
    elif first in 0xc2..0xdf:
      if not continuation(index + 1): return false
      index += 2
    elif first == 0xe0:
      if index + 2 >= value.len or ord(value[index + 1]) notin 0xa0..0xbf or
          not continuation(index + 2): return false
      index += 3
    elif first in 0xe1..0xec or first in 0xee..0xef:
      if not continuation(index + 1) or not continuation(index +
          2): return false
      index += 3
    elif first == 0xed:
      if index + 2 >= value.len or ord(value[index + 1]) notin 0x80..0x9f or
          not continuation(index + 2): return false
      index += 3
    elif first == 0xf0:
      if index + 3 >= value.len or ord(value[index + 1]) notin 0x90..0xbf or
          not continuation(index + 2) or not continuation(index +
              3): return false
      index += 4
    elif first in 0xf1..0xf3:
      if not continuation(index + 1) or not continuation(index + 2) or
          not continuation(index + 3): return false
      index += 4
    elif first == 0xf4:
      if index + 3 >= value.len or ord(value[index + 1]) notin 0x80..0x8f or
          not continuation(index + 2) or not continuation(index +
              3): return false
      index += 4
    else:
      return false
  true

proc `$`*(id: NodeId): string = string(id)
proc `==`*(left, right: NodeId): bool = string(left) == string(right)
proc nodeId*(value: string): NodeId = NodeId(value)

proc sourceSpan*(byteStart, byteEnd, lineStart, columnStart, lineEnd,
    columnEnd: int): SourceSpan =
  if byteStart < 0 or byteEnd < byteStart:
    raise newException(ModelError, "source span byte bounds are invalid")
  if lineStart < 1 or lineEnd < lineStart or columnStart < 1 or columnEnd < 1:
    raise newException(ModelError, "source span line or column bounds are invalid")
  if lineStart == lineEnd and columnEnd < columnStart:
    raise newException(ModelError, "source span columns are reversed")
  SourceSpan(knownField: true, byteStartField: byteStart,
    byteEndField: byteEnd, lineStartField: lineStart,
    columnStartField: columnStart, lineEndField: lineEnd,
    columnEndField: columnEnd)

proc sourceSpanFromBounds*(content: string; byteStart,
    byteEnd: int): SourceSpan =
  if byteStart < 0 or byteEnd < byteStart or byteEnd > content.len:
    raise newException(ModelError, "source span exceeds content bounds")
  proc locationAt(past: int): tuple[line, column: int] =
    result = (1, 1)
    var index = 0
    while index < past:
      if content[index] == '\r':
        inc result.line
        result.column = 1
        if index + 1 < past and content[index + 1] == '\n':
          inc index
      elif content[index] == '\n':
        inc result.line
        result.column = 1
      else:
        inc result.column
      inc index
  let first = locationAt(byteStart)
  let last = locationAt(byteEnd)
  sourceSpan(byteStart, byteEnd, first.line, first.column, last.line,
    last.column)

proc sourceIndex*(content: string): SourceIndex =
  result.lineStartsField = @[0]
  result.contentLengthField = content.len
  var index = 0
  while index < content.len:
    if content[index] == '\r':
      inc index
      if index < content.len and content[index] == '\n':
        result.crlfMiddlesField.add(index)
        inc index
      result.lineStartsField.add(index)
    elif content[index] == '\n':
      inc index
      result.lineStartsField.add(index)
    else:
      inc index

proc spanFor*(index: SourceIndex; byteStart, byteEnd: int): SourceSpan =
  if byteStart < 0 or byteEnd < byteStart or
      byteEnd > index.contentLengthField:
    raise newException(ModelError, "source span exceeds indexed content bounds")
  proc locationAt(offset: int): tuple[line, column: int] =
    var lower = 0
    var upper = index.lineStartsField.high
    while lower <= upper:
      let middle = lower + (upper - lower) div 2
      if index.lineStartsField[middle] <= offset:
        lower = middle + 1
      else:
        upper = middle - 1
    let lineIndex = max(upper, 0)
    var middleLower = 0
    var middleUpper = index.crlfMiddlesField.high
    while middleLower <= middleUpper:
      let middle = middleLower + (middleUpper - middleLower) div 2
      if index.crlfMiddlesField[middle] < offset:
        middleLower = middle + 1
      elif index.crlfMiddlesField[middle] > offset:
        middleUpper = middle - 1
      else:
        return (lineIndex + 2, 1)
    (lineIndex + 1, offset - index.lineStartsField[lineIndex] + 1)
  let first = locationAt(byteStart)
  let last = locationAt(byteEnd)
  sourceSpan(byteStart, byteEnd, first.line, first.column, last.line,
    last.column)

proc unknownSourceSpan*(): SourceSpan = SourceSpan()
proc isKnown*(span: SourceSpan): bool = span.knownField
proc byteStart*(span: SourceSpan): int = span.byteStartField
proc byteEnd*(span: SourceSpan): int = span.byteEndField
proc lineStart*(span: SourceSpan): int = span.lineStartField
proc columnStart*(span: SourceSpan): int = span.columnStartField
proc lineEnd*(span: SourceSpan): int = span.lineEndField
proc columnEnd*(span: SourceSpan): int = span.columnEndField

proc copySequence[T](items: seq[T]): seq[T] =
  result = newSeqOfCap[T](items.len)
  for item in items:
    result.add(item)

proc copyMetadata(value: OrderedTable[string, string]): OrderedTable[string, string] =
  result = initOrderedTable[string, string]()
  for key, item in value:
    result[key] = item

proc id*(node: InlineNode): NodeId = node.idField
proc kind*(node: InlineNode): InlineKind = node.kindField
proc children*(node: InlineNode): seq[InlineNode] = node.childrenField.copySequence
proc span*(node: InlineNode): SourceSpan = node.spanField
proc text*(node: InlineNode): string = node.textField
proc destination*(node: InlineNode): string = node.destinationField
proc title*(node: InlineNode): string = node.titleField
proc formatName*(node: InlineNode): string = node.formatNameField
proc rawInline*(node: InlineNode): string = node.rawInlineField

proc id*(node: BlockNode): NodeId = node.idField
proc kind*(node: BlockNode): BlockKind = node.kindField
proc blocks*(node: BlockNode): seq[BlockNode] = node.blocksField.copySequence
proc inlines*(node: BlockNode): seq[InlineNode] = node.inlinesField.copySequence
proc span*(node: BlockNode): SourceSpan = node.spanField
proc level*(node: BlockNode): int = node.levelField
proc start*(node: BlockNode): int = node.startField
proc language*(node: BlockNode): string = node.languageField
proc code*(node: BlockNode): string = node.codeField
proc formatName*(node: BlockNode): string = node.formatNameField
proc rawBlock*(node: BlockNode): string = node.rawBlockField

proc metadata*(document: Document): OrderedTable[string, string] =
  document.metadataField.copyMetadata

proc blocks*(document: Document): seq[BlockNode] = document.blocksField.copySequence
proc span*(document: Document): SourceSpan = document.spanField

proc textNode*(id, value: string; span = unknownSourceSpan()): InlineNode =
  InlineNode(idField: id.nodeId, kindField: inlineText, textField: value,
    spanField: span)

proc emphasisNode*(id: string; children: seq[InlineNode];
    span = unknownSourceSpan()): InlineNode =
  InlineNode(idField: id.nodeId, kindField: inlineEmphasis,
    childrenField: children.copySequence, spanField: span)

proc strongNode*(id: string; children: seq[InlineNode];
    span = unknownSourceSpan()): InlineNode =
  InlineNode(idField: id.nodeId, kindField: inlineStrong,
    childrenField: children.copySequence, spanField: span)

proc codeNode*(id, value: string; span = unknownSourceSpan()): InlineNode =
  InlineNode(idField: id.nodeId, kindField: inlineCode, textField: value,
    spanField: span)

proc linkNode*(id, destination: string; children: seq[InlineNode]; title = "";
    span = unknownSourceSpan()): InlineNode =
  InlineNode(idField: id.nodeId, kindField: inlineLink,
    destinationField: destination, titleField: title,
    childrenField: children.copySequence, spanField: span)

proc softBreakNode*(id: string; span = unknownSourceSpan()): InlineNode =
  InlineNode(idField: id.nodeId, kindField: inlineSoftBreak, spanField: span)

proc hardBreakNode*(id: string; span = unknownSourceSpan()): InlineNode =
  InlineNode(idField: id.nodeId, kindField: inlineHardBreak, spanField: span)

proc inlineExtensionNode*(id, formatName, raw: string;
    span = unknownSourceSpan()): InlineNode =
  InlineNode(idField: id.nodeId, kindField: inlineExtension,
    formatNameField: formatName, rawInlineField: raw, spanField: span)

proc paragraph*(id: string; children: seq[InlineNode];
    span = unknownSourceSpan()): BlockNode =
  BlockNode(idField: id.nodeId, kindField: blockParagraph,
    inlinesField: children.copySequence, spanField: span)

proc heading*(id: string; level: int; children: seq[InlineNode];
    span = unknownSourceSpan()): BlockNode =
  if level notin 1..6:
    raise newException(ModelError, "heading level must be between 1 and 6")
  BlockNode(idField: id.nodeId, kindField: blockHeading, levelField: level,
    inlinesField: children.copySequence, spanField: span)

proc unorderedList*(id: string; items: seq[BlockNode];
    span = unknownSourceSpan()): BlockNode =
  BlockNode(idField: id.nodeId, kindField: blockUnorderedList,
    blocksField: items.copySequence, spanField: span)

proc orderedList*(id: string; start: int; items: seq[BlockNode];
    span = unknownSourceSpan()): BlockNode =
  if start < 0:
    raise newException(ModelError, "ordered-list start cannot be negative")
  BlockNode(idField: id.nodeId, kindField: blockOrderedList, startField: start,
    blocksField: items.copySequence, spanField: span)

proc quoteBlock*(id: string; children: seq[BlockNode];
    span = unknownSourceSpan()): BlockNode =
  BlockNode(idField: id.nodeId, kindField: blockQuote,
    blocksField: children.copySequence, spanField: span)

proc codeBlock*(id, code: string; language = "";
    span = unknownSourceSpan()): BlockNode =
  BlockNode(idField: id.nodeId, kindField: blockCode,
    languageField: language, codeField: code, spanField: span)

proc thematicBreak*(id: string; span = unknownSourceSpan()): BlockNode =
  BlockNode(idField: id.nodeId, kindField: blockThematicBreak, spanField: span)

proc blockExtensionNode*(id, formatName, raw: string;
    span = unknownSourceSpan()): BlockNode =
  BlockNode(idField: id.nodeId, kindField: blockExtension,
    formatNameField: formatName, rawBlockField: raw, spanField: span)

proc newDocument*(blocks: seq[BlockNode] = @[];
    metadata = initOrderedTable[string, string]();
    span = unknownSourceSpan()): Document =
  Document(blocksField: blocks.copySequence,
    metadataField: metadata.copyMetadata, spanField: span)

proc spanContains(parent, child: SourceSpan): bool =
  not parent.isKnown or not child.isKnown or
    (parent.byteStart <= child.byteStart and child.byteEnd <= parent.byteEnd)

proc validate*(document: Document; limits = DefaultParseLimits) =
  # `< 1` for every field, `maxDecodedBytes` included. Zero was accepted there
  # while the others required one, so a ParseLimits built without naming that
  # field -- Nim leaves an int at zero -- rejected every document with
  # "decoded text limit exceeded", a message about a limit the caller never
  # set. Refusing the limits themselves says where the mistake is.
  if limits.maxNestingDepth < 1 or limits.maxNodes < 1 or
      limits.maxDecodedBytes < 1:
    raise newException(ModelError, "parse limits must be positive and consistent")
  var identifiers = initHashSet[string]()
  var count = 0
  var decodedBytes = 0

  proc requireValidUtf8(value, context: string) =
    if not value.isValidUtf8:
      raise newException(ModelError, context & " is not valid UTF-8")

  for key, value in document.metadataField:
    requireValidUtf8(key, "metadata key")
    requireValidUtf8(value, "metadata value")
    decodedBytes += key.len + value.len

  proc accept(id: NodeId; depth: int) =
    if depth > limits.maxNestingDepth:
      raise newException(ModelError, "document nesting limit exceeded")
    if $id == "":
      raise newException(ModelError, "node identifier cannot be empty")
    requireValidUtf8($id, "node identifier")
    if $id in identifiers:
      raise newException(ModelError, "duplicate node identifier: " & $id)
    identifiers.incl($id)
    inc count
    if count > limits.maxNodes:
      raise newException(ModelError, "document node limit exceeded")

  proc visitInline(node: InlineNode; depth: int; parentSpan: SourceSpan) =
    if node == nil:
      raise newException(ModelError, "inline node cannot be nil")
    accept(node.idField, depth)
    if not parentSpan.spanContains(node.spanField):
      raise newException(ModelError, "inline source span exceeds its parent")
    requireValidUtf8(node.textField, "inline text")
    requireValidUtf8(node.destinationField, "link destination")
    requireValidUtf8(node.titleField, "link title")
    requireValidUtf8(node.formatNameField, "inline extension format")
    requireValidUtf8(node.rawInlineField, "inline extension payload")
    case node.kindField
    of inlineText, inlineCode:
      if node.childrenField.len > 0:
        raise newException(ModelError, "text and code nodes cannot have children")
      decodedBytes += node.textField.len
    of inlineEmphasis, inlineStrong:
      if node.childrenField.len == 0:
        raise newException(ModelError, "formatted inline nodes require children")
    of inlineLink:
      decodedBytes += node.destinationField.len + node.titleField.len
    of inlineSoftBreak, inlineHardBreak:
      if node.childrenField.len > 0:
        raise newException(ModelError, "break nodes cannot have children")
    of inlineExtension:
      if node.formatNameField.len == 0:
        raise newException(ModelError, "inline extension format cannot be empty")
      if node.childrenField.len > 0:
        raise newException(ModelError, "inline extension nodes cannot have children")
      decodedBytes += node.formatNameField.len + node.rawInlineField.len
    for child in node.childrenField:
      visitInline(child, depth + 1, node.spanField)

  proc visitBlock(node: BlockNode; depth: int; parentSpan: SourceSpan) =
    if node == nil:
      raise newException(ModelError, "block node cannot be nil")
    accept(node.idField, depth)
    if not parentSpan.spanContains(node.spanField):
      raise newException(ModelError, "block source span exceeds its parent")
    requireValidUtf8(node.languageField, "code language")
    requireValidUtf8(node.codeField, "code block")
    requireValidUtf8(node.formatNameField, "block extension format")
    requireValidUtf8(node.rawBlockField, "block extension payload")
    case node.kindField
    of blockHeading:
      if node.levelField notin 1..6:
        raise newException(ModelError, "heading level must be between 1 and 6")
      if node.blocksField.len > 0:
        raise newException(ModelError, "heading nodes cannot contain blocks")
    of blockParagraph:
      if node.blocksField.len > 0:
        raise newException(ModelError, "paragraph nodes cannot contain blocks")
    of blockOrderedList:
      if node.startField < 0:
        raise newException(ModelError, "ordered-list start cannot be negative")
      if node.inlinesField.len > 0:
        raise newException(ModelError, "list nodes cannot contain direct inlines")
    of blockUnorderedList, blockQuote:
      if node.inlinesField.len > 0:
        raise newException(ModelError,
          "list and quote nodes cannot contain direct inlines")
    of blockCode:
      if node.inlinesField.len > 0 or node.blocksField.len > 0:
        raise newException(ModelError, "code blocks cannot contain child nodes")
      decodedBytes += node.languageField.len + node.codeField.len
    of blockThematicBreak:
      if node.inlinesField.len > 0 or node.blocksField.len > 0:
        raise newException(ModelError,
          "thematic breaks cannot contain child nodes")
    of blockExtension:
      if node.formatNameField.len == 0:
        raise newException(ModelError, "block extension format cannot be empty")
      if node.inlinesField.len > 0 or node.blocksField.len > 0:
        raise newException(ModelError, "block extensions cannot contain child nodes")
      decodedBytes += node.formatNameField.len + node.rawBlockField.len
    for inline in node.inlinesField:
      visitInline(inline, depth + 1, node.spanField)
    for childBlock in node.blocksField:
      visitBlock(childBlock, depth + 1, node.spanField)

  for blockNode in document.blocksField:
    visitBlock(blockNode, 1, document.spanField)
  if decodedBytes > limits.maxDecodedBytes:
    raise newException(ModelError, "decoded text limit exceeded")
