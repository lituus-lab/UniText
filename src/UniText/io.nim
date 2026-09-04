## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import UniText/[codec, detect, model]
import UniText/codecs/[asciidoc, markdown, restructured_text, rtf]

proc codecInfo*(format: TextFormat): CodecInfo =
  case format
  of formatMarkdown: MarkdownCodec
  of formatRestructuredText: RestructuredTextCodec
  of formatAsciiDoc: AsciiDocCodec
  of formatRtf: RtfCodec
  of formatUnknown: raise newException(CodecError, "unknown text format has no codec")

proc parseDocument*(content: string; format = formatUnknown; path = "";
    limits = DefaultParseLimits): ParseResult =
  let selected = if format == formatUnknown: content.detectFormat(
      path).format else: format
  case selected
  of formatMarkdown: parseMarkdown(content, limits)
  of formatRestructuredText: parseRestructuredText(content, limits)
  of formatAsciiDoc: parseAsciiDoc(content, limits)
  of formatRtf: parseRtf(content, limits)
  of formatUnknown: raise newException(CodecError, "text format could not be detected")

proc serializeDocument*(document: Document;
    format: TextFormat): SerializeResult =
  case format
  of formatMarkdown: serializeMarkdown(document)
  of formatRestructuredText: serializeRestructuredText(document)
  of formatAsciiDoc: serializeAsciiDoc(document)
  of formatRtf: serializeRtf(document)
  of formatUnknown: raise newException(CodecError, "cannot serialize an unknown text format")

proc convertDocument*(content: string; source, target: TextFormat; path = "";
    limits = DefaultParseLimits): SerializeResult =
  let parsed = parseDocument(content, source, path, limits)
  result = serializeDocument(parsed.document, target)
  result.diagnostics = parsed.diagnostics & result.diagnostics
