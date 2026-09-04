## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/[os, strutils, tables, unittest]
import UniText
import UniText/codecs/shared

suite "Versioned JSON interchange":
  test "round-trips a parsed document without semantic or identifier loss":
    let path = currentSourcePath.parentDir.parentDir / "fixtures" /
        "equivalent" / "sample.md"
    let source = parseMarkdown(readFile(path)).document
    let encoded = source.toInterchangeString(pretty = true)
    let decoded = fromInterchangeString(encoded)
    check decoded.blocks.len == source.blocks.len
    check decoded.blocks[0].id == source.blocks[0].id
    check decoded.blocks[1].inlines[1].kind == inlineStrong
    check decoded.blocks[1].inlines[7].kind == inlineLink
    check decoded.blocks[1].inlines[7].destination == "https://example.com"
    check decoded.blocks[1].blockText == source.blocks[1].blockText
    check decoded.span.isKnown
    check decoded.blocks[0].span.byteStart == source.blocks[0].span.byteStart
    check decoded.blocks[1].inlines[1].span.byteEnd ==
      source.blocks[1].inlines[1].span.byteEnd
    check "\"schema\": \"unitext.document\"" in encoded
    check "\"version\": 2" in encoded

  test "rejects malformed, unknown, and structurally invalid payloads":
    expect InterchangeError: discard fromInterchangeString("{")
    expect InterchangeError:
      discard fromInterchangeString("""{"schema":"other","version":1,"metadata":{},"blocks":[]}""")
    expect InterchangeError:
      discard fromInterchangeString("""{"schema":"unitext.document","version":2,"metadata":{},"span":null,"blocks":[{"id":"x","kind":"unknown","span":null}]}""")
    expect InterchangeError:
      discard fromInterchangeString(repeat("[", 1_000) & repeat("]", 1_000))
    expect InterchangeError:
      discard fromInterchangeString("[]", ParseLimits(maxInputBytes: 10,
        maxNestingDepth: 0, maxNodes: 1, maxDecodedBytes: 10))

  test "does not treat structural characters inside strings as nesting":
    let document = fromInterchangeString(
      """{"schema":"unitext.document","version":2,"metadata":{"literal":"[[[{{{\""},"span":null,"blocks":[]}""")
    check document.metadata["literal"] == "[[[{{{\""

suite "the caller's nesting limit is the limit":
  test "a document within a raised limit is not refused by a hidden cap":
    # The preflight capped the effective depth at 256 whatever the caller
    # asked, so a limit above about 127 levels reported a nesting violation
    # the caller had not set. Nothing in that scan recurses, so the cap bought
    # nothing.
    let parsed = parseDocument("# Title\n\nA paragraph.\n", formatMarkdown)
    let deep = toInterchangeString(parsed.document)
    # 200 levels asked for, and the document is far shallower: it must pass.
    let restored = fromInterchangeString(deep, ParseLimits(
      maxInputBytes: 1_000_000, maxNestingDepth: 200, maxNodes: 10_000,
      maxDecodedBytes: 1_000_000))
    check restored.blocks.len == 2
