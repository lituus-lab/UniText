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

Two shapes. The stateless one converts a string and hands the result back; the
handle-based one keeps a document open so a caller can parse once, edit, and
serialize several times without paying for a reparse.

```c
char *unitext_convert(const char *content, int source, int target);
char *unitext_convert_report(const char *content, int source, int target);

void *unitext_document_parse(const char *content, int format);
char *unitext_document_serialize(void *document, int format);
char *unitext_document_to_json(void *document);
void  unitext_document_destroy(void *document);

int         unitext_status(void);
const char *unitext_last_error(void);
void        unitext_cleanup(void *value);
```

`unitext_convert` gives the converted text; `unitext_convert_report` gives the
text *and* the diagnostics, which is what a caller wants whenever the target
carries less than the source.

## Three rules about memory

- **Every `char *` is yours**, released with `unitext_cleanup` exactly once.
- **A document handle is yours too**, released with `unitext_document_destroy`.
- **NULL means it failed.** The reason is `unitext_status` and
  `unitext_last_error`; no Nim exception crosses the boundary.

## Driven from C
"""

nbCode:
  echo run("cc -Iinclude -o build/book_c_demo examples/c/demo.c libUniText.a" &
          " && ./build/book_c_demo")

nbText: """
No Nim runtime call appears in that program. Every entry point initializes the
runtime itself, once, through a platform once-primitive: the library is built
`--noMain`, which suppresses the constructor a shared library would otherwise
get, so without that guard the first call would run against globals nobody had
set up.
"""

nbSave
