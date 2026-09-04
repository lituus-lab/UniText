## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/[os, unittest]
import UniText

suite "Bounded format detection":
  test "detects every equivalent fixture":
    let fixtures = currentSourcePath.parentDir.parentDir / "fixtures" / "equivalent"
    for item in [
      ("sample.md", formatMarkdown),
      ("sample.rst", formatRestructuredText),
      ("sample.adoc", formatAsciiDoc),
      ("sample.rtf", formatRtf)]:
      let path = fixtures / item[0]
      let detection = detectFormat(readFile(path), path)
      check detection.format == item[1]
      check detection.confidence >= 0.5

  test "does not guess arbitrary plain text":
    let detection = detectFormat("A plain paragraph without format markers.")
    check detection.format == formatUnknown
    check detection.confidence == 0.0
