## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/[tables, unittest]
import UniText

suite "Neutral document model":
  test "validates unique stable identifiers and heading levels":
    let document = newDocument(@[
      heading("heading-1", 1, @[textNode("text-1", "Portable document")]),
      paragraph("paragraph-1", @[textNode("text-2", "Portable content")])])
    document.validate
    expect ModelError:
      discard heading("invalid", 7, @[])

  test "rejects duplicate identifiers and resource excess":
    let duplicate = newDocument(@[
      paragraph("same", @[textNode("same", "duplicate")])])
    expect ModelError: duplicate.validate

    let oversized = newDocument(@[
      paragraph("paragraph", @[textNode("text", "too large")])])
    expect ModelError:
      oversized.validate(ParseLimits(maxInputBytes: 100, maxNestingDepth: 10,
        maxNodes: 10, maxDecodedBytes: 2))

  test "constructs every portable node without exposing variant internals":
    let rich = paragraph("paragraph", @[
      textNode("text", "A "),
      strongNode("strong", @[textNode("strong-text", "strong")]),
      emphasisNode("emphasis", @[textNode("emphasis-text", " idea")]),
      codeNode("code", "value"),
      linkNode("link", "https://example.com", @[textNode("label", "link")])])
    let document = newDocument(@[
      heading("heading", 2, @[textNode("title", "Title")]), rich,
      unorderedList("list", @[paragraph("item", @[textNode("item-text",
          "item")])]),
      codeBlock("block-code", "echo 1", "nim"), thematicBreak("break")])
    document.validate
    check document.blocks.len == 5
    expect ModelError:
      discard orderedList("ordered", -1, @[])

  test "counts link and metadata resources against decoded limits":
    var metadata = initOrderedTable[string, string]()
    metadata["title"] = "metadata"
    let document = newDocument(@[
      paragraph("paragraph", @[linkNode("link", "https://example.com", @[],
          "title")])],
      metadata)
    expect ModelError:
      document.validate(ParseLimits(maxInputBytes: 100, maxNestingDepth: 10,
        maxNodes: 10, maxDecodedBytes: 1))

  test "keeps the AST immutable across constructor and accessor boundaries":
    var inlineInput = @[textNode("text", "value")]
    let paragraphNode = paragraph("paragraph", inlineInput)
    inlineInput.add(textNode("outside", "mutation"))
    check paragraphNode.inlines.len == 1

    var blockInput = @[paragraphNode]
    var metadataInput = initOrderedTable[string, string]()
    metadataInput["title"] = "original"
    let document = newDocument(blockInput, metadataInput)
    blockInput.add(thematicBreak("outside-block"))
    metadataInput["title"] = "changed"
    check document.blocks.len == 1
    check document.metadata["title"] == "original"

    var returnedBlocks = document.blocks
    returnedBlocks.add(thematicBreak("returned-block"))
    var returnedInlines = document.blocks[0].inlines
    returnedInlines.add(textNode("returned-inline", "mutation"))
    var returnedText = document.blocks[0].inlines[0].text
    returnedText[0] = 'X'
    var returnedMetadata = document.metadata
    returnedMetadata["title"] = "returned"
    check document.blocks.len == 1
    check document.blocks[0].inlines.len == 1
    check document.blocks[0].inlines[0].text == "value"
    check document.metadata["title"] == "original"
    check not compiles(document.blocks = @[])
    check not compiles(paragraphNode.inlines = @[])
    check not compiles(paragraphNode.kind = blockCode)
    check not compiles(paragraphNode.inlines[0].text = "changed")

  test "validates source span containment":
    let childSpan = sourceSpan(20, 24, 2, 1, 2, 5)
    let parentSpan = sourceSpan(0, 10, 1, 1, 1, 11)
    let document = newDocument(@[
      paragraph("paragraph", @[textNode("text", "value", childSpan)],
        parentSpan)
    ], span = sourceSpan(0, 30, 1, 1, 3, 1))
    expect ModelError:
      document.validate

  test "indexes LF, CRLF, and CR source locations without rescanning":
    let content = "a\r\nb\nc\rd"
    let index = content.sourceIndex
    for first in 0 .. content.len:
      for past in first .. content.len:
        let scanned = sourceSpanFromBounds(content, first, past)
        let indexed = index.spanFor(first, past)
        check indexed.byteStart == scanned.byteStart
        check indexed.byteEnd == scanned.byteEnd
        check indexed.lineStart == scanned.lineStart
        check indexed.columnStart == scanned.columnStart
        check indexed.lineEnd == scanned.lineEnd
        check indexed.columnEnd == scanned.columnEnd

  test "accepts Unicode scalars and rejects malformed UTF-8 everywhere":
    check "Café 😀".isValidUtf8
    check not ("\xc0\x80").isValidUtf8
    check not ("\xed\xa0\x80").isValidUtf8
    check not ("\xf4\x90\x80\x80").isValidUtf8
    let malformed = newDocument(@[
      paragraph("paragraph", @[textNode("text", "\xfc")])])
    expect ModelError:
      malformed.validate

    var metadata = initOrderedTable[string, string]()
    metadata["valid"] = "\xf0\x28\x8c\xbc"
    expect ModelError:
      newDocument(metadata = metadata).validate

suite "parse limits are checked before any document is":
  test "every field must be positive, maxDecodedBytes included":
    # Nim leaves an int at zero, so a ParseLimits built without naming a field
    # is a limit of zero on it. That used to be accepted for maxDecodedBytes
    # alone, and every document then failed with "decoded text limit
    # exceeded" -- a message about a limit the caller never set.
    let partial = ParseLimits(maxInputBytes: 1024, maxNestingDepth: 8,
      maxNodes: 100)
    expect ModelError:
      validate(emptyDocument(), partial)

  test "maxInputBytes counts as much as the other three":
    # It was the one field `validate` did not look at, so a zero there passed
    # the check that exists to catch exactly that.
    expect ModelError:
      validate(emptyDocument(), ParseLimits(maxNestingDepth: 8, maxNodes: 100,
        maxDecodedBytes: 1024))

  test "a fully named one is accepted":
    let complete = ParseLimits(maxInputBytes: 1024, maxNestingDepth: 8,
      maxNodes: 100, maxDecodedBytes: 1024)
    validate(emptyDocument(), complete)
