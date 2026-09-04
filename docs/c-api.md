# C API

Include `UniText.h`, call `unitext_init` once, and destroy every returned document handle with
`unitext_document_destroy`. Document edits are immutable: each successful edit returns a new owned
handle and leaves the input handle unchanged.

All string-producing functions use a two-call buffer protocol. Call with `NULL, 0` to obtain the
required byte count, allocate that many bytes, then call again. The count includes the trailing
NUL. A zero return indicates an error; inspect `unitext_last_status` and `unitext_last_error`.

Use `unitext_document_serialize_report` or `unitext_convert_report` when format loss matters. Their
JSON result contains `content` and `diagnostics` fields. The ABI is versioned independently through
`UNITEXT_ABI_VERSION` and `unitext_abi_version`.

Version 1.0 of the ABI is single-threaded. Handles and error state must not be shared across
concurrent calls.
