## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/[json, os, sequtils, strutils, unittest]
import UniText
import UniText/codecs/shared

proc formatOf(value: string): TextFormat =
  case value
  of "markdown": formatMarkdown
  of "rst": formatRestructuredText
  of "asciidoc": formatAsciiDoc
  of "rtf": formatRtf
  else: formatUnknown

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

proc plain(document: Document): string =
  document.blocks.mapIt(it.plain).join("\n")

proc sourceMapsComplete(document: Document): bool =
  if not document.span.isKnown:
    return false
  proc inlineComplete(node: InlineNode): bool =
    node.span.isKnown and node.children.allIt(it.inlineComplete)
  proc blockComplete(node: BlockNode): bool =
    node.span.isKnown and node.inlines.allIt(it.inlineComplete) and
      node.blocks.allIt(it.blockComplete)
  document.blocks.allIt(it.blockComplete)

suite "Pinned official corpus projection":
  test "matches every selected upstream semantic case":
    let path = currentSourcePath.parentDir.parentDir / "fixtures" / "official" /
      "cases-v1.json"
    let corpus = parseFile(path)
    check corpus["schema"].getStr == "unitext.official-corpus"
    check corpus["sources"].len == 4
    check corpus["cases"].len >= 20
    for fixture in corpus["cases"]:
      let id = fixture["id"].getStr
      let content = fixture["input"].getStr
      let format = fixture["format"].getStr.formatOf
      checkpoint(id)
      check format != formatUnknown
      let document = parseDocument(content, format).document
      check document.sourceMapsComplete
      check document.blocks.mapIt(it.kind.kindName) ==
        fixture["expected_kinds"].getElems.mapIt(it.getStr)
      check document.plain == fixture["expected_plain"].getStr

