# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Python binding for bounded structured-document conversion."""
from enum import IntEnum

from ._core import (Document, abi_version, convert as _convert,
                    convert_report as _convert_report, detect as _detect, version)


class Format(IntEnum):
    AUTO = 0
    MARKDOWN = 1
    RESTRUCTURED_TEXT = 2
    ASCIIDOC = 3
    RTF = 4


__version__ = version()


def detect(data, path=None):
    """Return ``(Format, confidence)`` for bytes and optional filename evidence."""
    if not isinstance(data, bytes):
        raise TypeError("data must be bytes")
    value, confidence = _detect(data, path)
    return Format(value), confidence


def parse(data, format=Format.AUTO, path=None):
    """Parse bytes into an owned document handle."""
    if not isinstance(data, bytes):
        raise TypeError("data must be bytes")
    return Document.parse(data, int(format), path)


def from_json(data):
    """Restore a document from the versioned UniText JSON interchange."""
    if not isinstance(data, bytes):
        raise TypeError("data must be bytes")
    return Document.from_json(data)


def diagnostics(document):
    """Return the parsing diagnostics associated with a document handle."""
    import json
    if not isinstance(document, Document):
        raise TypeError("document must be a Document")
    return json.loads(document.diagnostics_json())


def serialize_with_report(document, format):
    """Return serialized content and explicit loss diagnostics."""
    import json
    if not isinstance(document, Document):
        raise TypeError("document must be a Document")
    return json.loads(document.serialize_report_json(int(format)))


def convert(data, source_format, target_format):
    """Convert bytes through the neutral document model."""
    if not isinstance(data, bytes):
        raise TypeError("data must be bytes")
    return _convert(data, int(source_format), int(target_format))


def convert_with_report(data, source_format, target_format):
    """Return a dictionary containing converted content and loss diagnostics."""
    import json
    if not isinstance(data, bytes):
        raise TypeError("data must be bytes")
    return json.loads(_convert_report(data, int(source_format), int(target_format)))


__all__ = ["Document", "Format", "abi_version", "convert", "convert_with_report", "detect",
           "diagnostics", "from_json", "parse", "serialize_with_report", "version",
           "__version__"]
