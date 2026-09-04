// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
#include "UniText.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;

/* check() records and carries on, which is what an assertion about a value
   wants and the opposite of what an allocation wants: the next line
   dereferences the pointer. allocated() reports through check() and answers
   whether it is safe to go on. */
static int allocated(const void *pointer, const char *message);

static void check(int condition, const char *message) {
  if (condition) {
    printf("ok   %s\n", message);
  } else {
    printf("FAIL %s\n", message);
    failures++;
  }
}

static int allocated(const void *pointer, const char *message) {
  check(pointer != NULL, message);
  return pointer != NULL;
}

int main(void) {
  const char *markdown =
      "# Portable document\n\nText with **weight** and `code`.\n";
  double confidence = 0.0;
  unitext_document document;
  size_t required;
  char *buffer;

  check(unitext_init() == 1, "runtime initialization");
  check(unitext_init() == 1, "idempotent runtime initialization");
  check(strcmp(unitext_version(), UNITEXT_VERSION) == 0, "version agreement");
  check(unitext_abi_version() == UNITEXT_ABI_VERSION, "ABI version agreement");
  check(unitext_detect(markdown, strlen(markdown), "sample.md", &confidence) ==
        UNITEXT_FORMAT_MARKDOWN, "Markdown detection");
  check(confidence >= 0.5, "detection confidence");

  document = unitext_document_parse(markdown, strlen(markdown),
                                    UNITEXT_FORMAT_MARKDOWN, NULL);
  check(document != NULL, "document parse");
  required = unitext_document_to_json(document, NULL, 0);
  check(required > 1, "JSON size query");
  buffer = (char *)malloc(required);
  if (!allocated(buffer, "JSON allocation")) return 1;
  check(unitext_document_to_json(document, buffer, required) == required,
        "JSON buffer write");
  check(strstr(buffer, "unitext.document") != NULL, "JSON schema");
  free(buffer);

  {
    unitext_document edited = unitext_document_replace_text(
        document, "edit-1", "heading-1-text", "Edited document");
    check(edited != NULL, "immutable text edit");
    required = unitext_document_serialize(edited, UNITEXT_FORMAT_MARKDOWN, NULL, 0);
    buffer = (char *)malloc(required);
    if (!allocated(buffer, "buffer allocation")) return 1;
    unitext_document_serialize(edited, UNITEXT_FORMAT_MARKDOWN, buffer, required);
    check(strstr(buffer, "# Edited document") != NULL, "edited serialization");
    free(buffer);
    unitext_document_destroy(edited);
  }

  required = unitext_document_diagnostics_json(document, NULL, 0);
  buffer = (char *)malloc(required);
  if (!allocated(buffer, "buffer allocation")) return 1;
  check(unitext_document_diagnostics_json(document, buffer, required) == required,
        "diagnostic buffer write");
  check(strcmp(buffer, "[]") == 0, "empty parse diagnostics");
  free(buffer);

  required = unitext_document_serialize(document, UNITEXT_FORMAT_ASCIIDOC, NULL, 0);
  buffer = (char *)malloc(required);
  if (!allocated(buffer, "buffer allocation")) return 1;
  check(unitext_document_serialize(document, UNITEXT_FORMAT_ASCIIDOC, buffer,
                                   required) == required, "AsciiDoc serialization");
  check(strstr(buffer, "= Portable document") != NULL, "AsciiDoc heading");
  free(buffer);

  required = unitext_document_serialize_report(
      document, UNITEXT_FORMAT_RTF, NULL, 0);
  buffer = (char *)malloc(required);
  if (!allocated(buffer, "buffer allocation")) return 1;
  check(unitext_document_serialize_report(document, UNITEXT_FORMAT_RTF, buffer,
                                          required) == required,
        "serialization report write");
  check(strstr(buffer, "rtf.inline-code-loss") != NULL,
        "serialization loss diagnostic");
  free(buffer);
  unitext_document_destroy(document);

  required = unitext_convert_report(markdown, strlen(markdown),
                                    UNITEXT_FORMAT_MARKDOWN, UNITEXT_FORMAT_RTF,
                                    NULL, 0);
  buffer = (char *)malloc(required);
  if (!allocated(buffer, "buffer allocation")) return 1;
  check(unitext_convert_report(markdown, strlen(markdown),
                               UNITEXT_FORMAT_MARKDOWN, UNITEXT_FORMAT_RTF,
                               buffer, required) == required,
        "conversion report write");
  check(strstr(buffer, "rtf.") != NULL, "conversion loss diagnostic");
  free(buffer);

  document = unitext_document_parse("```", 3, UNITEXT_FORMAT_MARKDOWN, NULL);
  check(document == NULL, "malformed input rejection");
  check(unitext_last_status() != UNITEXT_STATUS_OK, "stable error status");
  check(strlen(unitext_last_error()) > 0, "stable error message");

  {
    const unsigned char malformed_utf8[] = {0xfc};
    document = unitext_document_parse(malformed_utf8, sizeof malformed_utf8,
                                      UNITEXT_FORMAT_MARKDOWN, NULL);
    check(document == NULL, "malformed UTF-8 rejection at ABI boundary");
    check(unitext_last_status() != UNITEXT_STATUS_OK,
          "malformed UTF-8 error confinement");
  }

  unitext_cleanup();
  if (failures == 0) {
    printf("\nAll C ABI tests passed.\n");
    return 0;
  }
  printf("\n%d C ABI test(s) failed.\n", failures);
  return 1;
}
