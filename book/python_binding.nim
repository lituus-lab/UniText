# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/[os, osproc, strutils]
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nb.title = "The Python surface"

const Root = currentSourcePath().parentDir.parentDir

proc run(command: string): string =
  let (output, code) = execCmdEx("cd " & Root.quoteShell & " && " & command)
  result = output.strip
  if code != 0:
    raise newException(OSError,
      "book: `" & command & "` exited " & $code & "\n" & result)

nbText: """
# The Python surface

A Cython extension over the C ABI. The JSON the C entry points return is
decoded here, so a caller gets dicts and lists rather than strings to parse,
and the `unitext_cleanup` discipline underneath is not something they ever have
to think about.
"""

nbCode:
  echo run("""PYTHONPATH=py python3 -c '
import unitext

source = b"# Title\n\nSome **strong** text and a [link](https://example.org).\n"

print("version: ", unitext.version())
print("detected:", unitext.detect(source))
print()
print(unitext.convert(source, unitext.Format.MARKDOWN,
                      unitext.Format.RESTRUCTURED_TEXT).decode())
'""")

nbText: """
Bytes, not `str`. A document arrives as a file or off a socket, and deciding
its encoding is the caller's business, not a default this library picks for
them -- so it refuses a `str` rather than guessing.

`detect` answers with a format *and* a confidence, for the same reason the Nim
API does: a short document is often genuinely ambiguous.

## The report is the point

`convert` gives the text. `convert_with_report` gives a dict with the text and
what had to be left behind -- the call to make whenever the target format
carries less than the source.
"""

nbCode:
  echo run("""PYTHONPATH=py python3 -c '
import unitext

source = b"# Title\n\nSome **strong** text, `code`, and a [link](https://example.org).\n"
report = unitext.convert_with_report(source, unitext.Format.MARKDOWN,
                                     unitext.Format.RTF)

print("diagnostics:", len(report["diagnostics"]))
for d in report["diagnostics"]:
    print(" ", d["severity"], d["code"], "at", d["node_id"])
    print("   ", d["message"])
'""")

nbText: """
Two warnings, each naming the construct and the node it came from. Nothing was
refused: the RTF came out, and it is the best this subset can make of that
input. What the caller gains is knowing what changed.

## The distribution

`pip install lituus-unitext`; the import name stays `unitext`. The wheel
bundles the shared library beside the extension and finds it through an rpath
relative to it, so an installed package needs nothing else on the system.
"""

nbSave
