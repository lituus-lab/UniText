# cython: language_level=3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
from libc.stddef cimport size_t
from libc.stdlib cimport malloc, free
from libc.string cimport strlen

cdef extern from "UniText.h":
    int unitext_init()
    const char *unitext_version()
    int unitext_abi_version()
    int unitext_last_status()
    const char *unitext_last_error()
    int unitext_detect(const void *data, size_t length, const char *path,
                       double *confidence)
    void *unitext_document_parse(const void *data, size_t length, int format,
                                 const char *path)
    void *unitext_document_from_json(const void *data, size_t length)
    void unitext_document_destroy(void *document)
    void *unitext_document_replace_text(void *document, const char *operation_id,
                                        const char *target_node_id,
                                        const char *value)
    void *unitext_document_remove_block(void *document, const char *operation_id,
                                        const char *target_node_id)
    void *unitext_document_insert_after_json(
        void *document, const char *operation_id, const char *target_node_id,
        const void *payload, size_t payload_length)
    size_t unitext_document_to_json(void *document, char *destination,
                                    size_t capacity)
    size_t unitext_document_diagnostics_json(void *document, char *destination,
                                             size_t capacity)
    size_t unitext_document_serialize(void *document, int format,
                                      char *destination, size_t capacity)
    size_t unitext_document_serialize_report(void *document, int format,
                                             char *destination, size_t capacity)
    size_t unitext_convert(const void *data, size_t length, int source_format,
                           int target_format, char *destination, size_t capacity)
    size_t unitext_convert_report(const void *data, size_t length,
                                  int source_format, int target_format,
                                  char *destination, size_t capacity)


unitext_init()


cdef str error_message():
    cdef const char *message = unitext_last_error()
    if message == NULL:
        return "UniText operation failed"
    return (<bytes>message).decode("utf-8", "replace")


cdef bytes write_document(void *handle, int format, int operation):
    cdef size_t required
    cdef char *buffer
    if operation == 1:
        required = unitext_document_to_json(handle, NULL, 0)
    elif operation == 2:
        required = unitext_document_diagnostics_json(handle, NULL, 0)
    elif operation == 3:
        required = unitext_document_serialize_report(handle, format, NULL, 0)
    else:
        required = unitext_document_serialize(handle, format, NULL, 0)
    if required == 0:
        raise ValueError(error_message())
    buffer = <char *>malloc(required)
    if buffer == NULL:
        raise MemoryError("unable to allocate the UniText output buffer")
    try:
        if operation == 1:
            if unitext_document_to_json(handle, buffer, required) == 0:
                raise ValueError(error_message())
        elif operation == 2:
            if unitext_document_diagnostics_json(handle, buffer, required) == 0:
                raise ValueError(error_message())
        elif operation == 3:
            if unitext_document_serialize_report(handle, format, buffer, required) == 0:
                raise ValueError(error_message())
        else:
            if unitext_document_serialize(handle, format, buffer, required) == 0:
                raise ValueError(error_message())
        return buffer[:required - 1]
    finally:
        free(buffer)


def version():
    return (<bytes>unitext_version()).decode("ascii")


def abi_version():
    return unitext_abi_version()


def detect(bytes data, path=None):
    cdef bytes path_bytes = b"" if path is None else str(path).encode("utf-8")
    cdef const char *path_ptr = NULL
    cdef const char *data_ptr = data
    if path is not None:
        path_ptr = path_bytes
    cdef double confidence = 0.0
    cdef int format = unitext_detect(<const void *>data_ptr, len(data), path_ptr,
                                     &confidence)
    if format < 0:
        raise ValueError(error_message())
    return format, confidence


cdef class Document:
    cdef void *handle

    def __cinit__(self):
        self.handle = NULL

    def __dealloc__(self):
        if self.handle != NULL:
            unitext_document_destroy(self.handle)

    @staticmethod
    cdef Document wrap(void *handle):
        cdef Document result = Document.__new__(Document)
        result.handle = handle
        return result

    @classmethod
    def parse(cls, bytes data, int format=0, path=None):
        cdef bytes path_bytes = b"" if path is None else str(path).encode("utf-8")
        cdef const char *path_ptr = NULL
        cdef const char *data_ptr = data
        if path is not None:
            path_ptr = path_bytes
        cdef void *handle = unitext_document_parse(<const void *>data_ptr,
                                                   len(data), format, path_ptr)
        if handle == NULL:
            raise ValueError(error_message())
        return Document.wrap(handle)

    @classmethod
    def from_json(cls, bytes data):
        cdef const char *data_ptr = data
        cdef void *handle = unitext_document_from_json(<const void *>data_ptr,
                                                       len(data))
        if handle == NULL:
            raise ValueError(error_message())
        return Document.wrap(handle)

    def to_json(self):
        return write_document(self.handle, 0, 1)

    def diagnostics_json(self):
        return write_document(self.handle, 0, 2)

    def serialize(self, int format):
        return write_document(self.handle, format, 0)

    def serialize_report_json(self, int format):
        return write_document(self.handle, format, 3)

    def replace_text(self, operation_id, target_node_id, value):
        cdef bytes operation = str(operation_id).encode("utf-8")
        cdef bytes target = str(target_node_id).encode("utf-8")
        cdef bytes replacement = str(value).encode("utf-8")
        cdef void *edited = unitext_document_replace_text(
            self.handle, operation, target, replacement)
        if edited == NULL:
            raise ValueError(error_message())
        return Document.wrap(edited)

    def remove_block(self, operation_id, target_node_id):
        cdef bytes operation = str(operation_id).encode("utf-8")
        cdef bytes target = str(target_node_id).encode("utf-8")
        cdef void *edited = unitext_document_remove_block(
            self.handle, operation, target)
        if edited == NULL:
            raise ValueError(error_message())
        return Document.wrap(edited)

    def insert_after_json(self, operation_id, target_node_id, bytes payload):
        cdef bytes operation = str(operation_id).encode("utf-8")
        cdef bytes target = str(target_node_id).encode("utf-8")
        cdef const char *payload_ptr = payload
        cdef void *edited = unitext_document_insert_after_json(
            self.handle, operation, target, <const void *>payload_ptr, len(payload))
        if edited == NULL:
            raise ValueError(error_message())
        return Document.wrap(edited)


def convert(bytes data, int source_format, int target_format):
    cdef const char *data_ptr = data
    cdef size_t required = unitext_convert(<const void *>data_ptr, len(data), source_format,
                                           target_format, NULL, 0)
    cdef char *buffer
    if required == 0:
        raise ValueError(error_message())
    buffer = <char *>malloc(required)
    if buffer == NULL:
        raise MemoryError("unable to allocate the UniText output buffer")
    try:
        if unitext_convert(<const void *>data_ptr, len(data), source_format, target_format,
                           buffer, required) == 0:
            raise ValueError(error_message())
        return buffer[:required - 1]
    finally:
        free(buffer)


def convert_report(bytes data, int source_format, int target_format):
    cdef const char *data_ptr = data
    cdef size_t required = unitext_convert_report(<const void *>data_ptr, len(data),
                                                  source_format, target_format,
                                                  NULL, 0)
    cdef char *buffer
    if required == 0:
        raise ValueError(error_message())
    buffer = <char *>malloc(required)
    if buffer == NULL:
        raise MemoryError("unable to allocate the UniText output buffer")
    try:
        if unitext_convert_report(<const void *>data_ptr, len(data), source_format,
                                  target_format, buffer, required) == 0:
            raise ValueError(error_message())
        return buffer[:required - 1]
    finally:
        free(buffer)
