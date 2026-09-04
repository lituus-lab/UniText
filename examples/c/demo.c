// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
#include "UniText.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
  const char *source = "# Portable document\n\nText with **strong meaning**.\n";
  size_t size;
  char *output;
  unitext_init();
  size = unitext_convert(source, strlen(source), UNITEXT_FORMAT_MARKDOWN,
                         UNITEXT_FORMAT_ASCIIDOC, NULL, 0);
  if (size == 0) return 1;
  output = (char *)malloc(size);
  if (output == NULL) return 1;
  if (unitext_convert(source, strlen(source), UNITEXT_FORMAT_MARKDOWN,
                      UNITEXT_FORMAT_ASCIIDOC, output, size) == 0) return 1;
  fputs(output, stdout);
  free(output);
  return 0;
}
