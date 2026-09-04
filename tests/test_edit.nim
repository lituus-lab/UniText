## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/[os, unittest]
import UniText
import UniText/codecs/shared

suite "Immutable document edits":
  test "replaces text by stable node identifier without mutating the source":
    let path = currentSourcePath.parentDir.parentDir / "fixtures" /
        "equivalent" / "sample.md"
    let source = parseMarkdown(readFile(path)).document
    let edited = source.applyEdit(EditOperation(operationId: "edit-1",
      target: "heading-1-text".nodeId, kind: editReplaceText,
      value: "Edited document"))
    check source.blocks[0].blockText == "Portable document"
    check edited.document.blocks[0].blockText == "Edited document"
    check edited.change.beforeText == "Portable document"
    check edited.change.afterText == "Edited document"

  test "rejects unknown targets and missing operation identifiers":
    let document = parseMarkdown("# Title").document
    expect EditError:
      discard document.applyEdit(EditOperation(operationId: "edit-1",
        target: "missing".nodeId, kind: editReplaceText, value: "value"))
    expect EditError:
      discard document.applyEdit(EditOperation(operationId: "",
        target: "heading-1-text".nodeId, kind: editReplaceText, value: "value"))

  test "inserts and removes blocks without mutating the source":
    let source = parseMarkdown("# Title\n\nFirst paragraph.").document
    let inserted = source.insertBlockAfter("insert-1", "heading-1".nodeId,
      paragraph("inserted", @[textNode("inserted-text",
          "Inserted paragraph.")]))
    check source.blocks.len == 2
    check inserted.document.blocks.len == 3
    check inserted.document.blocks[1].id == "inserted".nodeId
    let removed = inserted.document.removeBlock("remove-1",
        "paragraph-2".nodeId)
    check removed.document.blocks.len == 2
    check inserted.document.blocks.len == 3

  test "rejects invalid structural operations and duplicate identifiers":
    let source = parseMarkdown("# Title").document
    expect EditError:
      discard source.insertBlockAfter("insert", "missing".nodeId,
        paragraph("new", @[textNode("new-text", "value")]))
    expect EditError:
      discard source.removeBlock("", "heading-1".nodeId)
    expect ModelError:
      discard source.insertBlockAfter("duplicate", "heading-1".nodeId,
        heading("heading-1", 1, @[textNode("different", "duplicate")]))
