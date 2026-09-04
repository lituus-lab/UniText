// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
// Coverage-guided target for the stable C ABI. The two-byte envelope is:
//   byte 0: Markdown, reStructuredText, AsciiDoc, RTF, auto-detect, or JSON
//   byte 1: serialization target (Markdown, reStructuredText, AsciiDoc, RTF)
#include "UniText.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

enum {
  INPUT_HEADER_BYTES = 2,
  MAX_ABI_OUTPUT_BYTES = 8 * 1024 * 1024
};

static void invariant(int condition) {
  if (!condition) {
    abort();
  }
}

static char *read_buffer(size_t required,
                         size_t (*writer)(unitext_document, char *, size_t),
                         unitext_document document) {
  char *buffer;
  size_t written;

  if (required == 0 || required > MAX_ABI_OUTPUT_BYTES) {
    return NULL;
  }
  buffer = (char *)malloc(required);
  if (buffer == NULL) {
    return NULL;
  }
  written = writer(document, buffer, required);
  invariant(written == required);
  invariant(buffer[required - 1] == '\0');
  return buffer;
}

static void exercise_document(unitext_document document, int target_format) {
  unitext_document restored;
  size_t required;
  char *buffer;

  required = unitext_document_diagnostics_json(document, NULL, 0);
  buffer = read_buffer(required, unitext_document_diagnostics_json, document);
  free(buffer);

  required = unitext_document_to_json(document, NULL, 0);
  buffer = read_buffer(required, unitext_document_to_json, document);
  if (buffer != NULL) {
    restored = unitext_document_from_json(buffer, required - 1);
    invariant(restored != NULL);
    unitext_document_destroy(restored);
    free(buffer);
  }

  required = unitext_document_serialize(document, target_format, NULL, 0);
  if (required > 0 && required <= MAX_ABI_OUTPUT_BYTES) {
    buffer = (char *)malloc(required);
    if (buffer != NULL) {
      invariant(unitext_document_serialize(document, target_format, buffer,
                                           required) == required);
      invariant(buffer[required - 1] == '\0');
      free(buffer);
    }
  }

  required =
      unitext_document_serialize_report(document, target_format, NULL, 0);
  if (required > 0 && required <= MAX_ABI_OUTPUT_BYTES) {
    buffer = (char *)malloc(required);
    if (buffer != NULL) {
      invariant(unitext_document_serialize_report(
                    document, target_format, buffer, required) == required);
      invariant(buffer[required - 1] == '\0');
      free(buffer);
    }
  }
}

int LLVMFuzzerInitialize(int *argc, char ***argv) {
  (void)argc;
  (void)argv;
  invariant(unitext_init() == 1);
  return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  const void *payload;
  size_t payload_size;
  int input_mode;
  int target_format;
  unitext_document document;

  if (size < INPUT_HEADER_BYTES) {
    return 0;
  }
  input_mode = data[0] % 6;
  target_format = 1 + (data[1] % 4);
  payload = data + INPUT_HEADER_BYTES;
  payload_size = size - INPUT_HEADER_BYTES;

  if (input_mode == 5) {
    document = unitext_document_from_json(payload, payload_size);
  } else {
    double confidence = 0.0;
    (void)unitext_detect(payload, payload_size, NULL, &confidence);
    document = unitext_document_parse(payload, payload_size, input_mode, NULL);
  }

  if (document != NULL) {
    exercise_document(document, target_format);
    unitext_document_destroy(document);
  }
  return 0;
}
