// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
#ifndef UNITEXT_H
#define UNITEXT_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define UNITEXT_VERSION_MAJOR 0
#define UNITEXT_VERSION_MINOR 2
#define UNITEXT_VERSION_PATCH 0
#define UNITEXT_VERSION "0.2.0"
#define UNITEXT_ABI_VERSION 1
#define UNITEXT_VERSION_AT_LEAST(major, minor, patch) \
  ((UNITEXT_VERSION_MAJOR > (major)) || \
   (UNITEXT_VERSION_MAJOR == (major) && UNITEXT_VERSION_MINOR > (minor)) || \
   (UNITEXT_VERSION_MAJOR == (major) && UNITEXT_VERSION_MINOR == (minor) && \
    UNITEXT_VERSION_PATCH >= (patch)))

typedef void *unitext_document;

typedef enum unitext_format {
  UNITEXT_FORMAT_AUTO = 0,
  UNITEXT_FORMAT_MARKDOWN = 1,
  UNITEXT_FORMAT_RESTRUCTURED_TEXT = 2,
  UNITEXT_FORMAT_ASCIIDOC = 3,
  UNITEXT_FORMAT_RTF = 4
} unitext_format;

typedef enum unitext_status {
  UNITEXT_STATUS_OK = 0,
  UNITEXT_STATUS_INVALID_ARGUMENT = 1,
  UNITEXT_STATUS_PARSE_ERROR = 2,
  UNITEXT_STATUS_UNSUPPORTED = 3,
  UNITEXT_STATUS_EDIT_ERROR = 4,
  UNITEXT_STATUS_INTERNAL_ERROR = 5
} unitext_status;

/* The ABI is single-threaded. Call once before every other function. */
int unitext_init(void);
void unitext_cleanup(void);
const char *unitext_version(void);
int unitext_abi_version(void);
int unitext_last_status(void);
/* The returned pointer is valid until the next ABI call. Do not free it. */
const char *unitext_last_error(void);

/* Returns a unitext_format value, or -1 on error. */
int unitext_detect(const void *data, size_t length, const char *path,
                   double *confidence);

unitext_document unitext_document_parse(const void *data, size_t length,
                                        int format, const char *path);
unitext_document unitext_document_from_json(const void *data, size_t length);
void unitext_document_destroy(unitext_document document);
/* Immutable edits return a new owned handle; the input remains valid. */
unitext_document unitext_document_replace_text(unitext_document document,
                                               const char *operation_id,
                                               const char *target_node_id,
                                               const char *value);
unitext_document unitext_document_remove_block(unitext_document document,
                                               const char *operation_id,
                                               const char *target_node_id);
/* The payload is a versioned interchange document containing exactly one
 * top-level block. */
unitext_document unitext_document_insert_after_json(
    unitext_document document, const char *operation_id,
    const char *target_node_id, const void *payload, size_t payload_length);

/* Buffer functions return bytes required including the trailing NUL.
 * Pass NULL/0 to query the size. A zero return indicates an error. */
size_t unitext_document_to_json(unitext_document document, char *destination,
                                size_t capacity);
size_t unitext_document_diagnostics_json(unitext_document document,
                                         char *destination, size_t capacity);
size_t unitext_document_serialize(unitext_document document, int format,
                                  char *destination, size_t capacity);
/* JSON object with content and serialization diagnostics fields. */
size_t unitext_document_serialize_report(unitext_document document, int format,
                                         char *destination, size_t capacity);
size_t unitext_convert(const void *data, size_t length, int source_format,
                       int target_format, char *destination, size_t capacity);
/* JSON object with content and diagnostics fields. */
size_t unitext_convert_report(const void *data, size_t length, int source_format,
                              int target_format, char *destination,
                              size_t capacity);

#ifdef __cplusplus
}
#endif

#endif
