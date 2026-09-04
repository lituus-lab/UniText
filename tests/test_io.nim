## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/[os, unittest]
import UniText
import UniText/codecs/shared

proc semanticSnapshot(document: Document): seq[(BlockKind, string)] =
  for node in document.blocks:
    var value = node.blockText
    if node.kind == blockUnorderedList:
      for item in node.blocks: value.add("|" & item.blockText)
    result.add((node.kind, value))

suite "Format-neutral I/O and conversion":
  test "dispatches every codec and produces one common semantic snapshot":
    let fixtures = currentSourcePath.parentDir.parentDir / "fixtures" / "equivalent"
    var reference: seq[(BlockKind, string)]
    for filename in ["sample.md", "sample.rst", "sample.adoc", "sample.rtf"]:
      let path = fixtures / filename
      let parsed = parseDocument(readFile(path), path = path)
      let snapshot = parsed.document.semanticSnapshot
      if reference.len == 0: reference = snapshot
      else: check snapshot == reference

  test "converts Markdown and reports only target-specific loss":
    let path = currentSourcePath.parentDir.parentDir / "fixtures" /
        "equivalent" / "sample.md"
    for target in [formatMarkdown, formatRestructuredText, formatAsciiDoc, formatRtf]:
      let converted = convertDocument(readFile(path), formatMarkdown, target)
      check converted.content.len > 0
      if target == formatRtf:
        check converted.diagnostics.len >= 1
      else:
        check converted.diagnostics.len == 0

  test "rejects undetectable input and unknown serialization":
    expect CodecError: discard parseDocument("plain text")
    expect CodecError:
      discard serializeDocument(newDocument(), formatUnknown)
