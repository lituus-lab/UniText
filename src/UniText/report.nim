## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/json
import UniText/model

proc severityName(severity: DiagnosticSeverity): string =
  case severity
  of diagnosticInfo: "info"
  of diagnosticWarning: "warning"
  of diagnosticError: "error"

proc diagnosticToJson*(diagnostic: Diagnostic): JsonNode =
  result = %*{
    "severity": severityName(diagnostic.severity),
    "code": diagnostic.code,
    "message": diagnostic.message,
    "node_id": $diagnostic.nodeId
  }
  if diagnostic.span.isKnown:
    result["span"] = %*{
      "byte_start": diagnostic.span.byteStart,
      "byte_end": diagnostic.span.byteEnd,
      "line_start": diagnostic.span.lineStart,
      "column_start": diagnostic.span.columnStart,
      "line_end": diagnostic.span.lineEnd,
      "column_end": diagnostic.span.columnEnd
    }
  else:
    result["span"] = newJNull()

proc diagnosticsToJson*(diagnostics: openArray[Diagnostic]): JsonNode =
  result = newJArray()
  for diagnostic in diagnostics: result.add(diagnostic.diagnosticToJson)

proc diagnosticsToString*(diagnostics: openArray[Diagnostic];
    pretty = false): string =
  let tree = diagnostics.diagnosticsToJson
  if pretty: tree.pretty else: $tree

proc conversionReportToString*(content: string; diagnostics: openArray[
    Diagnostic]; pretty = false): string =
  let tree = %*{"content": content, "diagnostics": diagnostics.diagnosticsToJson}
  if pretty: tree.pretty else: $tree
