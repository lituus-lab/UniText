## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/[os, strutils, unittest]
import UniText
import UniText/codecs/shared

suite "Markdown subset codec":
  test "preserves the portable inline intersection":
    let path = currentSourcePath.parentDir.parentDir / "fixtures" /
        "equivalent" / "sample.md"
    let parsed = parseMarkdown(readFile(path))
    check parsed.document.blocks.len == 4
    check parsed.document.blocks[0].kind == blockHeading
    check parsed.document.blocks[0].blockText == "Portable document"
    check parsed.document.blocks[2].kind == blockUnorderedList
    check parsed.document.blocks[3].kind == blockCode
    check parsed.diagnostics.len == 0
    let inlines = parsed.document.blocks[1].inlines
    check inlines.len == 9
    check inlines[1].kind == inlineStrong
    check inlines[3].kind == inlineEmphasis
    check inlines[5].kind == inlineCode
    check inlines[7].kind == inlineLink
    check inlines[7].destination == "https://example.com"
    let serialized = serializeMarkdown(parsed.document)
    check "# Portable document" in serialized.content
    check "```nim" in serialized.content
    check "**strong text**" in serialized.content
    check "[link](https://example.com)" in serialized.content
    check serialized.diagnostics.len == 0

  test "rejects unterminated fences and byte-limit excess":
    expect CodecError: discard parseMarkdown("```nim\necho 1")
    expect CodecError:
      discard parseMarkdown("large", ParseLimits(maxInputBytes: 2,
        maxNestingDepth: 10,
        maxNodes: 10, maxDecodedBytes: 10))

  test "does not misclassify a backtick-bearing info string as a fence":
    let parsed = parseMarkdown("```a``text`````\n")
    check parsed.document.blocks.len == 1
    check parsed.document.blocks[0].kind == blockParagraph

  test "treats non-heading hash lines as paragraph text without stalling":
    let parsed = parseMarkdown("####### not a heading\n#missing-space\n")
    check parsed.document.blocks.len == 1
    check parsed.document.blocks[0].blockText ==
      "####### not a heading #missing-space"

  test "round-trips literal Markdown punctuation as text":
    let value = "# a *literal* [marker](not-a-link) with `ticks` and \\slashes"
    let document = newDocument(@[
      paragraph("paragraph", @[textNode("text", value)])
    ])
    let serialized = serializeMarkdown(document)
    let reparsed = parseMarkdown(serialized.content)
    check serialized.diagnostics.len == 0
    check reparsed.document.blocks.len == 1
    check reparsed.document.blocks[0].kind == blockParagraph
    check reparsed.document.blocks[0].inlines.len == 1
    check reparsed.document.blocks[0].inlines[0].kind == inlineText
    check reparsed.document.blocks[0].inlines[0].text == value

  test "chooses delimiters that cannot close code content":
    let document = newDocument(@[
      paragraph("paragraph", @[codeNode("inline-code", "left`right")]),
      codeBlock("code", "before\n```\nafter", "nim")
    ])
    let serialized = serializeMarkdown(document)
    let reparsed = parseMarkdown(serialized.content)
    check serialized.diagnostics.len == 0
    check "``left`right``" in serialized.content
    check "````nim" in serialized.content
    check reparsed.document.blocks.len == 2
    check reparsed.document.blocks[0].inlines.len == 1
    check reparsed.document.blocks[0].inlines[0].kind == inlineCode
    check reparsed.document.blocks[0].inlines[0].text == "left`right"
    check reparsed.document.blocks[1].kind == blockCode
    check reparsed.document.blocks[1].code == "before\n```\nafter"
