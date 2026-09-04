## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/[os, strutils, unittest]
import UniText
import UniText/codecs/shared

proc verifyCommon(document: Document) =
  check document.blocks.len == 4
  check document.blocks[0].kind == blockHeading
  check document.blocks[0].blockText == "Portable document"
  check document.blocks[2].kind == blockUnorderedList
  check document.blocks[3].kind == blockCode
  check document.blocks[3].language == "nim"
  let inlines = document.blocks[1].inlines
  check inlines.len == 9
  check inlines[1].kind == inlineStrong
  check inlines[3].kind == inlineEmphasis
  check inlines[5].kind == inlineCode
  check inlines[7].kind == inlineLink
  check inlines[7].destination == "https://example.com"

suite "Lightweight structured-text codecs":
  test "parses and serializes the reStructuredText fixture":
    let path = currentSourcePath.parentDir.parentDir / "fixtures" /
        "equivalent" / "sample.rst"
    let parsed = parseRestructuredText(readFile(path))
    parsed.document.verifyCommon
    check parsed.diagnostics.len == 0
    let serialized = serializeRestructuredText(parsed.document)
    check ".. code-block:: nim" in serialized.content
    check serialized.diagnostics.len == 0

  test "parses and serializes the AsciiDoc fixture":
    let path = currentSourcePath.parentDir.parentDir / "fixtures" /
        "equivalent" / "sample.adoc"
    let parsed = parseAsciiDoc(readFile(path))
    parsed.document.verifyCommon
    check parsed.diagnostics.len == 0
    let serialized = serializeAsciiDoc(parsed.document)
    check "[source,nim]" in serialized.content
    check serialized.diagnostics.len == 0

  test "rejects malformed source blocks":
    expect CodecError: discard parseAsciiDoc("[source,nim]\necho 1")

  test "preserves heading levels and semantic underline width":
    let asciidoc = parseAsciiDoc("=== Deep *strong* heading")
    check asciidoc.document.blocks[0].level == 3
    let rst = serializeRestructuredText(asciidoc.document)
    check "Deep **strong** heading\n~~~~~~~~~~~~~~~~~~~" in rst.content

  test "chooses an AsciiDoc source delimiter outside the code payload":
    let document = newDocument(@[
      codeBlock("code", "before\n----\nafter", "nim")
    ])
    let serialized = serializeAsciiDoc(document)
    let reparsed = parseAsciiDoc(serialized.content)
    check "-----" in serialized.content
    check serialized.diagnostics.len == 0
    check reparsed.document.blocks.len == 1
    check reparsed.document.blocks[0].code == "before\n----\nafter"

  test "reports inline semantics outside a target subset":
    let extension = inlineExtensionNode("extension", "fixture", "raw")
    let document = newDocument(@[
      paragraph("paragraph", @[
        textNode("text", "before"), softBreakNode("soft"), extension
      ])
    ])
    let serialized = serializeAsciiDoc(document)
    check serialized.diagnostics.len == 2
    check serialized.diagnostics[0].code == "asciidoc.soft-break-loss"
    check serialized.diagnostics[1].code == "asciidoc.extension-loss"

suite "round trips the review found broken":
  test "an rst heading carrying markup keeps its underline long enough":
    # The underline was sized from the plain text while the title line carries
    # the markup, so `# A **strong** title` came back as two paragraphs: the
    # parser wants the underline at least as long as the title.
    let rst = convertDocument("# A **strong** title\r\n\r\nBody.\r\n",
      formatMarkdown, formatRestructuredText).content
    let parsed = parseDocument(rst, formatRestructuredText)
    check parsed.document.blocks[0].kind == blockHeading
    check parsed.document.blocks[1].kind == blockParagraph

  test "a heading short enough to fall under the parser's floor still holds":
    let rst = convertDocument("# A\r\n", formatMarkdown,
      formatRestructuredText).content
    check parseDocument(rst, formatRestructuredText).document.blocks[0].kind ==
      blockHeading
