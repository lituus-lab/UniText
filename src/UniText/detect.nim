## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/[os, strutils]

type
  TextFormat* = enum
    formatUnknown
    formatMarkdown
    formatRestructuredText
    formatAsciiDoc
    formatRtf

  Detection* = object
    format*: TextFormat
    confidence*: float
    evidence*: seq[string]

proc formatFromExtension*(path: string): TextFormat =
  case path.splitFile.ext.toLowerAscii
  of ".md", ".markdown", ".mdown": formatMarkdown
  of ".rst", ".rest": formatRestructuredText
  of ".adoc", ".asciidoc", ".asc": formatAsciiDoc
  of ".rtf": formatRtf
  else: formatUnknown

proc detectFormat*(content: string; path = ""): Detection =
  let extensionFormat = path.formatFromExtension
  let prefix = content[0 ..< min(content.len, 4096)]
  if prefix.startsWith("{\\rtf"):
    return Detection(format: formatRtf, confidence: 1.0,
      evidence: @["RTF control-word signature"])

  var scores: array[TextFormat, int]
  if extensionFormat != formatUnknown:
    scores[extensionFormat] += 4
    result.evidence.add("recognized file extension")
  let lines = prefix.splitLines
  for index, line in lines:
    if line.startsWith("# ") or line.startsWith("``` ") or line == "```":
      scores[formatMarkdown] += 2
    if line.startsWith("= ") or line.startsWith("[source,") or line == "----":
      scores[formatAsciiDoc] += 2
    if line.startsWith(".. code-block::"):
      scores[formatRestructuredText] += 3
    if index > 0 and line.len > 2 and line.allCharsInSet({'=', '-', '~', '^',
        '"', '`', ':'}) and lines[index - 1].strip.len > 0:
      scores[formatRestructuredText] += 2

  var bestScore = 0
  for candidate in [formatMarkdown, formatRestructuredText, formatAsciiDoc, formatRtf]:
    if scores[candidate] > bestScore:
      bestScore = scores[candidate]
      result.format = candidate
  if bestScore > 0:
    result.confidence = min(0.95, bestScore.float / 8.0 + 0.35)
  else:
    result.format = formatUnknown
    result.confidence = 0.0
