/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 lituus-lab */
/* Run by book/surfaces.nim during the book build; its output is the page's. */
#include <stdio.h>
#include "UniText.h"

int main(void) {
  printf("unitext_version()            = %s\n", unitext_version());
  printf("unitext_fibonacci(10)        = %lld\n", unitext_fibonacci(10));
  printf("unitext_fibonacci(-1)        = %lld   (clamped, not an error)\n",
         unitext_fibonacci(-1));
  printf("unitext_fibonacci(200)       = %lld   (clamped to n = %d)\n",
         unitext_fibonacci(200), UNITEXT_FIB_MAX_N);
  return 0;
}
