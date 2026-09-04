## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/[json, tables]
import UniText/model

type InterchangeError* = object of ValueError

const InterchangeSchemaVersion* = 2

proc spanToJson(span: SourceSpan): JsonNode =
  if not span.isKnown:
    return newJNull()
  %*{
    "byte_start": span.byteStart,
    "byte_end": span.byteEnd,
    "line_start": span.lineStart,
    "column_start": span.columnStart,
    "line_end": span.lineEnd,
    "column_end": span.columnEnd,
  }

proc preflightJson(content: string; limits: ParseLimits) =
  # The caller's limit, doubled for the block-object-plus-child-array pair each
  # level costs, and not capped: a fixed 256 silently refused documents that
  # satisfied a higher limit, reporting a nesting violation the caller had not
  # asked for. Nothing here recurses -- the scan is a loop with a counter -- so
  # a deep document costs iterations, not stack.
  let maximumDepth = limits.maxNestingDepth * 2 + 8
  let maximumContainers = limits.maxNodes * 2 + 4_096
  var depth = 0
  var containers = 0
  var inString = false
  var escaped = false
  for character in content:
    if inString:
      if escaped:
        escaped = false
      elif character == '\\':
        escaped = true
      elif character == '"':
        inString = false
    else:
      case character
      of '"': inString = true
      of '{', '[':
        inc depth
        inc containers
        if depth > maximumDepth:
          raise newException(InterchangeError,
            "interchange JSON nesting limit exceeded")
        if containers > maximumContainers:
          raise newException(InterchangeError,
            "interchange JSON container limit exceeded")
      of '}', ']':
        dec depth
        if depth < 0:
          raise newException(InterchangeError,
            "invalid interchange JSON structure")
      else: discard

proc inlineKindName(kind: InlineKind): string =
  case kind
  of inlineText: "text"
  of inlineEmphasis: "emphasis"
  of inlineStrong: "strong"
  of inlineCode: "code"
  of inlineLink: "link"
  of inlineSoftBreak: "soft_break"
  of inlineHardBreak: "hard_break"
  of inlineExtension: "extension"

proc blockKindName(kind: BlockKind): string =
  case kind
  of blockHeading: "heading"
  of blockParagraph: "paragraph"
  of blockOrderedList: "ordered_list"
  of blockUnorderedList: "unordered_list"
  of blockQuote: "quote"
  of blockCode: "code"
  of blockThematicBreak: "thematic_break"
  of blockExtension: "extension"

proc inlineToJson(node: InlineNode): JsonNode =
  result = %*{"id": $node.id, "kind": inlineKindName(node.kind),
    "span": spanToJson(node.span)}
  case node.kind
  of inlineText, inlineCode: result["text"] = %node.text
  of inlineLink:
    result["destination"] = %node.destination
    result["title"] = %node.title
  of inlineExtension:
    result["format"] = %node.formatName
    result["raw"] = %node.rawInline
  else: discard
  if node.children.len > 0:
    result["children"] = newJArray()
    for child in node.children: result["children"].add(inlineToJson(child))

proc blockToJson(node: BlockNode): JsonNode =
  result = %*{"id": $node.id, "kind": blockKindName(node.kind),
    "span": spanToJson(node.span)}
  case node.kind
  of blockHeading: result["level"] = %node.level
  of blockOrderedList: result["start"] = %node.start
  of blockCode:
    result["language"] = %node.language
    result["code"] = %node.code
  of blockExtension:
    result["format"] = %node.formatName
    result["raw"] = %node.rawBlock
  else: discard
  if node.inlines.len > 0:
    result["inlines"] = newJArray()
    for inline in node.inlines: result["inlines"].add(inlineToJson(inline))
  if node.blocks.len > 0:
    result["blocks"] = newJArray()
    for child in node.blocks: result["blocks"].add(blockToJson(child))

proc toInterchangeJson*(document: Document): JsonNode =
  document.validate
  var metadata = newJObject()
  for key, value in document.metadata: metadata[key] = %value
  result = %*{"schema": "unitext.document", "version": InterchangeSchemaVersion,
    "metadata": metadata, "blocks": newJArray(),
    "span": spanToJson(document.span)}
  for blockNode in document.blocks: result["blocks"].add(blockToJson(blockNode))

proc toInterchangeString*(document: Document; pretty = false): string =
  let tree = document.toInterchangeJson
  if pretty: tree.pretty else: $tree

proc requireObject(node: JsonNode; context: string) =
  if node.kind != JObject:
    raise newException(InterchangeError, context & " must be an object")

proc requireString(node: JsonNode; key, context: string): string =
  if key notin node or node[key].kind != JString:
    raise newException(InterchangeError, context & "." & key & " must be a string")
  node[key].getStr

proc requireInteger(node: JsonNode; key, context: string): int =
  if key notin node or node[key].kind != JInt:
    raise newException(InterchangeError, context & "." & key &
      " must be an integer")
  node[key].getInt

proc spanFromJson(node: JsonNode; context: string): SourceSpan =
  if node.kind == JNull:
    return unknownSourceSpan()
  node.requireObject(context)
  try:
    sourceSpan(node.requireInteger("byte_start", context),
      node.requireInteger("byte_end", context),
      node.requireInteger("line_start", context),
      node.requireInteger("column_start", context),
      node.requireInteger("line_end", context),
      node.requireInteger("column_end", context))
  except ModelError as error:
    raise newException(InterchangeError, "invalid " & context & ": " & error.msg)

proc requireSpan(node: JsonNode; context: string): SourceSpan =
  if "span" notin node:
    raise newException(InterchangeError, context & ".span is required")
  spanFromJson(node["span"], context & ".span")

proc inlineFromJson(node: JsonNode): InlineNode =
  node.requireObject("inline node")
  let id = node.requireString("id", "inline node")
  let kind = node.requireString("kind", "inline node")
  let span = node.requireSpan("inline node")
  var children: seq[InlineNode]
  if "children" in node:
    if node["children"].kind != JArray:
      raise newException(InterchangeError, "inline node.children must be an array")
    for child in node["children"]:
      children.add(inlineFromJson(child))
  case kind
  of "text":
    result = textNode(id, node.requireString("text", "inline node"), span)
  of "code":
    result = codeNode(id, node.requireString("text", "inline node"), span)
  of "emphasis":
    result = emphasisNode(id, children, span)
  of "strong":
    result = strongNode(id, children, span)
  of "link":
    result = linkNode(id, node.requireString("destination", "inline node"),
      children, node.requireString("title", "inline node"), span)
  of "soft_break":
    result = softBreakNode(id, span)
  of "hard_break":
    result = hardBreakNode(id, span)
  of "extension":
    result = inlineExtensionNode(id,
      node.requireString("format", "inline node"),
      node.requireString("raw", "inline node"), span)
  else: raise newException(InterchangeError, "unknown inline kind: " & kind)

proc blockFromJson(node: JsonNode): BlockNode =
  node.requireObject("block node")
  let id = node.requireString("id", "block node")
  let kind = node.requireString("kind", "block node")
  let span = node.requireSpan("block node")
  var inlines: seq[InlineNode]
  var blocks: seq[BlockNode]
  if "inlines" in node:
    if node["inlines"].kind != JArray:
      raise newException(InterchangeError, "block node.inlines must be an array")
    for inline in node["inlines"]:
      inlines.add(inlineFromJson(inline))
  if "blocks" in node:
    if node["blocks"].kind != JArray:
      raise newException(InterchangeError, "block node.blocks must be an array")
    for child in node["blocks"]:
      blocks.add(blockFromJson(child))
  case kind
  of "heading":
    result = heading(id, node.requireInteger("level", "block node"), inlines,
      span)
  of "paragraph":
    result = paragraph(id, inlines, span)
  of "ordered_list":
    result = orderedList(id, node.requireInteger("start", "block node"),
      blocks, span)
  of "unordered_list":
    result = unorderedList(id, blocks, span)
  of "quote":
    result = quoteBlock(id, blocks, span)
  of "code":
    result = codeBlock(id, node.requireString("code", "block node"),
      node.requireString("language", "block node"), span)
  of "thematic_break":
    result = thematicBreak(id, span)
  of "extension":
    result = blockExtensionNode(id,
      node.requireString("format", "block node"),
      node.requireString("raw", "block node"), span)
  else: raise newException(InterchangeError, "unknown block kind: " & kind)

proc fromInterchangeJson*(root: JsonNode;
    limits = DefaultParseLimits): Document =
  root.requireObject("interchange root")
  if root.requireString("schema", "interchange root") != "unitext.document":
    raise newException(InterchangeError, "unsupported interchange schema")
  if "version" notin root or root["version"].kind != JInt or
      root["version"].getInt != InterchangeSchemaVersion:
    raise newException(InterchangeError, "unsupported interchange version")
  var metadata = initOrderedTable[string, string]()
  if "metadata" notin root or root["metadata"].kind != JObject:
    raise newException(InterchangeError, "interchange root.metadata must be an object")
  for key, value in root["metadata"]:
    if value.kind != JString:
      raise newException(InterchangeError, "metadata values must be strings")
    metadata[key] = value.getStr
  if "blocks" notin root or root["blocks"].kind != JArray:
    raise newException(InterchangeError, "interchange root.blocks must be an array")
  var blocks: seq[BlockNode]
  for blockNode in root["blocks"]:
    blocks.add(blockFromJson(blockNode))
  if "span" notin root:
    raise newException(InterchangeError, "interchange root.span is required")
  result = newDocument(blocks, metadata,
    spanFromJson(root["span"], "interchange root.span"))
  result.validate(limits)

proc fromInterchangeString*(content: string;
    limits = DefaultParseLimits): Document =
  if content.len > limits.maxInputBytes:
    raise newException(InterchangeError, "input byte limit exceeded")
  if limits.maxNestingDepth < 1 or limits.maxNodes < 1:
    raise newException(InterchangeError, "parse limits must be positive")
  preflightJson(content, limits)
  try:
    result = fromInterchangeJson(parseJson(content), limits)
  except JsonParsingError as error:
    raise newException(InterchangeError, "invalid interchange JSON: " & error.msg)
