## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/[os, strutils, unittest]
import UniText
import UniText/codecs/shared

suite "RTF styled subset codec":
  test "uses styles for block semantics and reports normalized inline formatting":
    let path = currentSourcePath.parentDir.parentDir / "fixtures" /
        "equivalent" / "sample.rtf"
    let parsed = parseRtf(readFile(path))
    check parsed.document.blocks.len == 4
    check parsed.document.blocks[0].kind == blockHeading
    check parsed.document.blocks[0].blockText == "Portable document"
    check parsed.document.blocks[2].kind == blockUnorderedList
    check parsed.document.blocks[3].kind == blockCode
    check parsed.diagnostics.len == 1
    check parsed.diagnostics[0].code == "rtf.inline-normalized"

    let serialized = serializeRtf(parsed.document)
    check serialized.content.startsWith("{\\rtf1")
    check "\\s1\\b Portable document" in serialized.content
    check serialized.diagnostics.len == 0
    let reparsed = parseRtf(serialized.content)
    check reparsed.document.blocks.len == 4

  test "rejects a missing signature and byte-limit excess":
    expect CodecError: discard parseRtf("plain text")
    expect CodecError:
      discard parseRtf("{\\rtf1}", ParseLimits(maxInputBytes: 2,
        maxNestingDepth: 10,
        maxNodes: 10, maxDecodedBytes: 10))

  test "round-trips Unicode through signed UTF-16 escapes":
    let value = "Café — 😀 \\ { }"
    let document = newDocument(@[
      paragraph("paragraph", @[textNode("text", value)])
    ])
    let serialized = serializeRtf(document)
    let reparsed = parseRtf(serialized.content)
    check "\\uc1" in serialized.content
    check "\\u233?" in serialized.content
    check "\\u-10179?\\u-8704?" in serialized.content
    check reparsed.document.blocks.len == 1
    check reparsed.document.blocks[0].blockText == value

  test "decodes ANSI bytes and suppresses ignored destinations and binary data":
    let parsed = parseRtf(
      "{\\rtf1\\ansi\\uc1 {\\*\\generator hidden;}Visible \\'e9 " &
      "{\\pict\\bin4 {}xx}\\u-10179?\\u-8704?\\par}")
    check parsed.document.blocks.len == 1
    check parsed.document.blocks[0].blockText == "Visible é 😀"
    check "hidden" notin parsed.document.blocks[0].blockText

suite "pard resets the paragraph style":
  test "a paragraph after pard is not another heading":
    # \pard resets paragraph properties, style among them. Ignoring it made
    # every later paragraph inherit \s1. Our own output hid it: serializeRtf
    # writes an explicit \s before each paragraph.
    const document = "{\\rtf1\\ansi \\s1 Title\\par \\pard Body\\par}"
    let parsed = parseDocument(document, formatRtf)
    check parsed.document.blocks[0].kind == blockHeading
    check parsed.document.blocks[1].kind == blockParagraph

  test "and a style set after it still applies":
    const document = "{\\rtf1\\ansi \\pard\\s2 Code\\par}"
    check parseDocument(document, formatRtf).document.blocks[0].kind == blockCode
