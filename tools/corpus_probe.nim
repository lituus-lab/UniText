## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/[json, os, sequtils, strutils]
import UniText
import UniText/codecs/shared

proc formatOf(value: string): TextFormat =
  case value
  of "markdown": formatMarkdown
  of "rst": formatRestructuredText
  of "asciidoc": formatAsciiDoc
  of "rtf": formatRtf
  else: raise newException(ValueError, "unsupported format: " & value)

proc kindName(kind: BlockKind): string =
  case kind
  of blockHeading: "heading"
  of blockParagraph: "paragraph"
  of blockOrderedList: "ordered_list"
  of blockUnorderedList: "unordered_list"
  of blockQuote: "quote"
  of blockCode: "code"
  of blockThematicBreak: "thematic_break"
  of blockExtension: "extension"

proc plain(node: BlockNode): string =
  if node.kind in {blockCode, blockExtension}:
    return node.blockText
  if node.inlines.len > 0:
    return node.inlines.plainText
  node.blocks.mapIt(it.plain).join("\n")

proc sourceMapsComplete(document: Document): bool =
  if not document.span.isKnown:
    return false
  proc inlineComplete(node: InlineNode): bool =
    node.span.isKnown and node.children.allIt(it.inlineComplete)
  proc blockComplete(node: BlockNode): bool =
    node.span.isKnown and node.inlines.allIt(it.inlineComplete) and
      node.blocks.allIt(it.blockComplete)
  document.blocks.allIt(it.blockComplete)

proc main() =
  if paramCount() != 1:
    raise newException(ValueError, "usage: corpus_probe FORMAT")
  let content = stdin.readAll
  let parsed = parseDocument(content, paramStr(1).formatOf)
  let document = parsed.document
  document.validate
  var kinds = newJArray()
  var values: seq[string]
  for blockNode in document.blocks:
    kinds.add(%blockNode.kind.kindName)
    values.add(blockNode.plain)
  stdout.write($(%*{
    "kinds": kinds,
    "plain": values.join("\n"),
    "source_maps_complete": document.sourceMapsComplete,
    "diagnostic_errors": parsed.diagnostics.countIt(
      it.severity == diagnosticError),
  }))

when isMainModule:
  main()
