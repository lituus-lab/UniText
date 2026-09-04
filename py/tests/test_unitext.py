# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import json

import pytest

import unitext


SOURCE = (b"# Portable document\n\nText with **strong meaning**, `code`, and "
          b"a [link](https://example.com).\n")


def test_version_and_detection():
    assert unitext.__version__ == "0.2.0"
    assert unitext.version() == "0.2.0"
    assert unitext.abi_version() == 1
    format, confidence = unitext.detect(SOURCE, "sample.md")
    assert format is unitext.Format.MARKDOWN
    assert confidence >= 0.5


def test_document_interchange_and_serialization():
    document = unitext.parse(SOURCE, unitext.Format.MARKDOWN)
    tree = json.loads(document.to_json())
    assert tree["schema"] == "unitext.document"
    assert tree["version"] == 2
    assert tree["span"] == {
        "byte_start": 0,
        "byte_end": len(SOURCE),
        "line_start": 1,
        "column_start": 1,
        "line_end": 4,
        "column_end": 1,
    }
    assert tree["blocks"][0]["span"]["byte_start"] == 0
    assert tree["blocks"][0]["inlines"][0]["span"]["byte_start"] == 2
    assert b"= Portable document" in document.serialize(unitext.Format.ASCIIDOC)
    serialization_report = unitext.serialize_with_report(
        document, unitext.Format.RTF)
    assert serialization_report["diagnostics"][0]["code"] == "rtf.inline-code-loss"
    restored = unitext.from_json(document.to_json())
    assert restored.serialize(unitext.Format.MARKDOWN).startswith(b"# Portable document")
    assert unitext.diagnostics(document) == []
    edited = document.replace_text("edit-1", "heading-1-text", "Edited document")
    assert edited.serialize(unitext.Format.MARKDOWN).startswith(b"# Edited document")
    assert document.serialize(unitext.Format.MARKDOWN).startswith(b"# Portable document")
    removed = document.remove_block("remove-1", "paragraph-2")
    assert removed.serialize(unitext.Format.MARKDOWN) == b"# Portable document\n\n"


def test_conversion_and_error_mapping():
    converted = unitext.convert(SOURCE, unitext.Format.MARKDOWN,
                                unitext.Format.RESTRUCTURED_TEXT)
    assert converted.startswith(b"Portable document\n=================")
    report = unitext.convert_with_report(SOURCE, unitext.Format.MARKDOWN,
                                         unitext.Format.RTF)
    assert report["content"].startswith("{\\rtf1")
    assert report["diagnostics"][0]["code"] == "rtf.inline-code-loss"
    with pytest.raises(ValueError, match="unterminated"):
        unitext.parse(b"```", unitext.Format.MARKDOWN)
    with pytest.raises(TypeError, match="bytes"):
        unitext.parse("not bytes")
