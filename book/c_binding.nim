# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/[os, osproc, strutils]
import lituus_theme

nbInit(theme = useNimibook)
useLituus()
nb.title = "The C surface"

const Root = currentSourcePath().parentDir.parentDir

proc run(command: string): string =
  ## A non-zero exit stops the book. Publishing a traceback as a page's
  ## "output", from a build that reported success, is the failure this raises
  ## to avoid.
  let (output, code) = execCmdEx("cd " & Root.quoteShell & " && " & command)
  result = output.strip
  if code != 0:
    raise newException(OSError,
      "book: `" & command & "` exited " & $code & "\n" & result)

nbText: """
# The C surface

A caller-supplied buffer, twice. Every function that produces text takes a
destination and a capacity and returns the bytes it needs, NUL included; pass
`NULL, 0` to ask for the size, allocate, and call again. Nothing is allocated
on your behalf and nothing has to be freed through this library.

```c
size_t unitext_convert(const void *data, size_t length,
                       int source_format, int target_format,
                       char *destination, size_t capacity);
size_t unitext_convert_report(const void *data, size_t length,
                              int source_format, int target_format,
                              char *destination, size_t capacity);

unitext_document unitext_document_parse(const void *data, size_t length,
                                        int format);
size_t unitext_document_serialize(unitext_document document, int format,
                                  char *destination, size_t capacity);
void   unitext_document_destroy(unitext_document document);

void        unitext_init(void);
int         unitext_status(void);
const char *unitext_last_error(void);
```

**Zero means it failed.** Not "empty": a successful call always needs at least
the terminating NUL, so a zero return is unambiguous, and the reason is in
`unitext_status` and `unitext_last_error`.

`unitext_convert` gives the converted text; `unitext_convert_report` gives a
JSON object with the text *and* the diagnostics — the call to make whenever
the target format carries less than the source.

## Two shapes

The functions above convert a string in one go. The `unitext_document_*` family
keeps a parsed document open instead, so a caller can parse once and serialize
several times, or edit in between, without paying for a reparse. A handle is
released with `unitext_document_destroy`, exactly once.

## Driven from C
"""

nbCode:
  echo run("cc -Iinclude -o build/book_c_demo examples/c/demo.c libUniText.a" &
          " && ./build/book_c_demo")

nbText: """
That program calls `unitext_init()` first. The library is built `--noMain`,
which suppresses the constructor a shared build would otherwise get, so nothing
initializes the Nim runtime on its own; the entry points guard themselves with
a platform once-primitive, and `unitext_init` is how a caller does it up front
rather than paying for the check on the first real call.
"""

nbSave
