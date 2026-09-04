## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/[json, strutils, unittest]
import UniText

suite "Machine-readable diagnostics":
  test "serializes stable diagnostic and conversion report fields":
    let document = parseMarkdown("# Title\n\nText with [link](https://example.com).").document
    let converted = serializeRtf(document)
    let report = parseJson(conversionReportToString(converted.content,
      converted.diagnostics))
    check report["content"].getStr.startsWith("{\\rtf1")
    check report["diagnostics"].len == 1
    check report["diagnostics"][0]["severity"].getStr == "warning"
    check report["diagnostics"][0]["code"].getStr == "rtf.link-loss"
