## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import UniText/model

type
  EditKind* = enum
    editReplaceText

  EditOperation* = object
    operationId*: string
    target*: NodeId
    case kind*: EditKind
    of editReplaceText:
      value*: string

  ChangeRecord* = object
    operationId*: string
    target*: NodeId
    beforeText*: string
    afterText*: string

  EditResult* = object
    document*: Document
    change*: ChangeRecord

  EditError* = object of ValueError

  StructureEditResult* = object
    document*: Document
    operationId*: string
    target*: NodeId
    inserted*: NodeId

proc cloneInline(node: InlineNode; operation: EditOperation; found: var bool;
    change: var ChangeRecord): InlineNode =
  if node == nil:
    return nil
  var children: seq[InlineNode]
  for child in node.children:
    children.add(cloneInline(child, operation, found, change))
  case node.kind
  of inlineText, inlineCode:
    var value = node.text
    var span = node.span
    if node.id == operation.target:
      found = true
      change = ChangeRecord(operationId: operation.operationId, target: node.id,
        beforeText: node.text, afterText: operation.value)
      value = operation.value
      span = unknownSourceSpan()
    if node.kind == inlineText:
      result = textNode($node.id, value, span)
    else:
      result = codeNode($node.id, value, span)
  of inlineEmphasis:
    result = emphasisNode($node.id, children, node.span)
  of inlineStrong:
    result = strongNode($node.id, children, node.span)
  of inlineLink:
    result = linkNode($node.id, node.destination, children, node.title, node.span)
  of inlineSoftBreak:
    result = softBreakNode($node.id, node.span)
  of inlineHardBreak:
    result = hardBreakNode($node.id, node.span)
  of inlineExtension:
    result = inlineExtensionNode($node.id, node.formatName, node.rawInline,
      node.span)

proc cloneBlock(node: BlockNode; operation: EditOperation; found: var bool;
    change: var ChangeRecord): BlockNode =
  if node == nil:
    return nil
  var inlines: seq[InlineNode]
  var blocks: seq[BlockNode]
  for inline in node.inlines:
    inlines.add(cloneInline(inline, operation, found, change))
  for child in node.blocks:
    blocks.add(cloneBlock(child, operation, found, change))
  case node.kind
  of blockHeading:
    result = heading($node.id, node.level, inlines, node.span)
  of blockParagraph:
    result = paragraph($node.id, inlines, node.span)
  of blockOrderedList:
    result = orderedList($node.id, node.start, blocks, node.span)
  of blockUnorderedList:
    result = unorderedList($node.id, blocks, node.span)
  of blockQuote:
    result = quoteBlock($node.id, blocks, node.span)
  of blockCode:
    result = codeBlock($node.id, node.code, node.language, node.span)
  of blockThematicBreak:
    result = thematicBreak($node.id, node.span)
  of blockExtension:
    result = blockExtensionNode($node.id, node.formatName, node.rawBlock,
      node.span)

proc applyEdit*(document: Document; operation: EditOperation): EditResult =
  if operation.operationId.len == 0:
    raise newException(EditError, "edit operation identifier cannot be empty")
  var found = false
  var blocks: seq[BlockNode]
  for blockNode in document.blocks:
    blocks.add(cloneBlock(blockNode, operation, found, result.change))
  if not found:
    raise newException(EditError, "edit target was not found: " &
      $operation.target)
  result.document = newDocument(blocks, document.metadata, document.span)
  result.document.validate

proc rebuildBlock(node: BlockNode; blocks: seq[BlockNode]): BlockNode =
  case node.kind
  of blockOrderedList:
    orderedList($node.id, node.start, blocks, node.span)
  of blockUnorderedList:
    unorderedList($node.id, blocks, node.span)
  of blockQuote:
    quoteBlock($node.id, blocks, node.span)
  else:
    node

proc insertBlockAfter*(document: Document; operationId: string; target: NodeId;
    newBlock: BlockNode): StructureEditResult =
  if operationId.len == 0:
    raise newException(EditError, "edit operation identifier cannot be empty")
  if newBlock == nil:
    raise newException(EditError, "inserted block cannot be nil")
  result.operationId = operationId
  result.target = target
  result.inserted = newBlock.id
  var found = false

  proc transform(nodes: seq[BlockNode]): seq[BlockNode] =
    for node in nodes:
      result.add(rebuildBlock(node, transform(node.blocks)))
      if node.id == target:
        found = true
        result.add(newBlock)

  result.document = newDocument(transform(document.blocks), document.metadata,
    document.span)
  if not found:
    raise newException(EditError, "edit target was not found: " & $target)
  result.document.validate
proc removeBlock*(document: Document; operationId: string;
    target: NodeId): StructureEditResult =
  if operationId.len == 0:
    raise newException(EditError, "edit operation identifier cannot be empty")
  result.operationId = operationId
  result.target = target
  var found = false

  proc transform(nodes: seq[BlockNode]): seq[BlockNode] =
    for node in nodes:
      if node.id == target:
        found = true
        continue
      result.add(rebuildBlock(node, transform(node.blocks)))

  result.document = newDocument(transform(document.blocks), document.metadata,
    document.span)
  if not found:
    raise newException(EditError, "edit target was not found: " & $target)
  result.document.validate
