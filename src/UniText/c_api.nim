# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## Stable C ABI. Keep in sync with include/UniText.h.
import ../UniText

const UniTextVersionC: cstring = "0.2.0"

type AbiDocument = ref object
  document: Document
  diagnostics: seq[Diagnostic]

var
  abiStatus: cint
  abiError: string

proc setError(status: cint; message: string) =
  abiStatus = status
  abiError = message

proc clearError() =
  abiStatus = 0
  abiError.setLen(0)

proc inputString(data: pointer; length: csize_t): string =
  if length == 0: return ""
  if data == nil: raise newException(ValueError, "input pointer is null")
  if uint64(length) > uint64(high(int)):
    raise newException(ValueError, "input length exceeds the platform limit")
  result = newString(int(length))
  copyMem(addr result[0], data, int(length))

proc formatFromC(value: cint): TextFormat =
  case value
  of 0: formatUnknown
  of 1: formatMarkdown
  of 2: formatRestructuredText
  of 3: formatAsciiDoc
  of 4: formatRtf
  else: raise newException(ValueError, "unknown format identifier")

proc formatToC(value: TextFormat): cint =
  case value
  of formatUnknown: 0
  of formatMarkdown: 1
  of formatRestructuredText: 2
  of formatAsciiDoc: 3
  of formatRtf: 4

proc pin(document: Document; diagnostics: seq[Diagnostic] = @[]): pointer =
  let handle = new(AbiDocument)
  handle.document = document
  handle.diagnostics = diagnostics
  GC_ref(handle)
  cast[pointer](handle)

proc documentOf(handle: pointer): Document =
  if handle == nil: raise newException(ValueError, "document handle is null")
  cast[AbiDocument](handle).document

proc diagnosticsOf(handle: pointer): seq[Diagnostic] =
  if handle == nil: raise newException(ValueError, "document handle is null")
  cast[AbiDocument](handle).diagnostics

proc writeBuffer(value: string; destination: pointer;
    capacity: csize_t): csize_t =
  let required = csize_t(value.len + 1)
  if destination == nil or capacity < required: return required
  if value.len > 0: copyMem(destination, unsafeAddr value[0], value.len)
  cast[ptr UncheckedArray[char]](destination)[value.len] = '\0'
  required

template guard(defaultValue: untyped; body: untyped): untyped =
  try:
    clearError()
    body
  except CodecError:
    setError(2, getCurrentExceptionMsg())
    defaultValue
  except InterchangeError:
    setError(2, getCurrentExceptionMsg())
    defaultValue
  except ModelError:
    setError(2, getCurrentExceptionMsg())
    defaultValue
  except EditError:
    setError(4, getCurrentExceptionMsg())
    defaultValue
  except ValueError:
    setError(1, getCurrentExceptionMsg())
    defaultValue
  except Exception:
    # No Nim exception may cross the C ABI, including a Defect raised by a
    # bounds/resource invariant in an imported codec.
    setError(5, getCurrentExceptionMsg())
    defaultValue


# A shared library runs NimMain from DllMain (Windows) or an ELF constructor;
# a static one has neither, so nothing initializes the Nim runtime. The first
# entry point then enters Nim code whose globals were never set up and the
# process faults. The static-library tasks pass -d:noAutoInit; shared
# builds must not, or NimMain runs twice.
when defined(noAutoInit):
  # A once primitive, not a plain flag: two threads reaching an entry point
  # together would both see the flag unset, both call NimMain, and the second
  # would enter Nim code the first had not finished initializing. The platform
  # primitives block the losers until the winner returns, which a flag cannot.
  #
  # C statics, not Nim globals: module initialization would reset a Nim one and
  # NimMain would run again. NimMain is declared here too — the generated
  # prototype comes after this section.
  {.emit: """/*VARSECTION*/
void NimMain(void);
#ifdef _WIN32
#  include <windows.h>
static INIT_ONCE unitext_runtime_once = INIT_ONCE_STATIC_INIT;
static BOOL CALLBACK unitext_runtime_init(PINIT_ONCE o, PVOID p, PVOID *c) {
  (void)o; (void)p; (void)c; NimMain(); return TRUE;
}
static void unitext_runtime_ensure(void) {
  InitOnceExecuteOnce(&unitext_runtime_once, unitext_runtime_init, NULL, NULL);
}
#else
#  include <pthread.h>
static pthread_once_t unitext_runtime_once = PTHREAD_ONCE_INIT;
static void unitext_runtime_init(void) { NimMain(); }
static void unitext_runtime_ensure(void) {
  pthread_once(&unitext_runtime_once, unitext_runtime_init);
}
#endif
""".}
  template ensureRuntime() =
    {.emit: "  unitext_runtime_ensure();".}
else:
  template ensureRuntime() = discard


{.push exportc, cdecl, dynlib, raises: [].}

proc unitext_init(): cint =
  ensureRuntime()
  clearError()
  1

proc unitext_cleanup() =
  ensureRuntime()
  discard

proc unitext_version(): cstring =
  ensureRuntime()
  UniTextVersionC

proc unitext_abi_version(): cint =
  ensureRuntime()
  1

proc unitext_last_status(): cint =
  ensureRuntime()
  abiStatus

proc unitext_last_error(): cstring =
  ensureRuntime()
  if abiError.len == 0: "" else: abiError.cstring

proc unitext_detect(data: pointer; length: csize_t; path: cstring;
    confidence: ptr cdouble): cint =
  ensureRuntime()
  guard(cint(-1)):
    let detection = detectFormat(inputString(data, length),
      if path == nil: "" else: $path)
    if confidence != nil: confidence[] = cdouble(detection.confidence)
    formatToC(detection.format)

proc unitext_document_parse(data: pointer; length: csize_t; format: cint;
    path: cstring): pointer =
  ensureRuntime()
  guard(cast[pointer](nil)):
    let requested = formatFromC(format)
    let parsed = parseDocument(inputString(data, length), requested,
      if path == nil: "" else: $path)
    pin(parsed.document, parsed.diagnostics)

proc unitext_document_from_json(data: pointer; length: csize_t): pointer =
  ensureRuntime()
  guard(cast[pointer](nil)):
    pin(fromInterchangeString(inputString(data, length)))

proc unitext_document_destroy(handle: pointer) =
  ensureRuntime()
  if handle != nil: GC_unref(cast[AbiDocument](handle))

proc unitext_document_replace_text(handle: pointer; operationId, target,
    value: cstring): pointer =
  ensureRuntime()
  guard(cast[pointer](nil)):
    if operationId == nil or target == nil or value == nil:
      raise newException(ValueError, "edit argument is null")
    let edited = documentOf(handle).applyEdit(EditOperation(
      operationId: $operationId,
      target: ($target).nodeId, kind: editReplaceText, value: $value))
    pin(edited.document)

proc unitext_document_remove_block(handle: pointer; operationId,
    target: cstring): pointer =
  ensureRuntime()
  guard(cast[pointer](nil)):
    if operationId == nil or target == nil:
      raise newException(ValueError, "edit argument is null")
    pin(documentOf(handle).removeBlock($operationId, ($target).nodeId).document)

proc unitext_document_insert_after_json(handle: pointer; operationId,
    target: cstring; data: pointer; length: csize_t): pointer =
  ensureRuntime()
  guard(cast[pointer](nil)):
    if operationId == nil or target == nil:
      raise newException(ValueError, "edit argument is null")
    let payload = fromInterchangeString(inputString(data, length))
    if payload.blocks.len != 1:
      raise newException(ValueError,
        "insert payload must contain exactly one top-level block")
    pin(documentOf(handle).insertBlockAfter($operationId, ($target).nodeId,
      payload.blocks[0]).document)

proc unitext_document_to_json(handle: pointer; destination: pointer;
    capacity: csize_t): csize_t =
  ensureRuntime()
  guard(csize_t(0)):
    writeBuffer(documentOf(handle).toInterchangeString, destination, capacity)

proc unitext_document_diagnostics_json(handle: pointer; destination: pointer;
    capacity: csize_t): csize_t =
  ensureRuntime()
  guard(csize_t(0)):
    writeBuffer(diagnosticsOf(handle).diagnosticsToString, destination, capacity)

proc unitext_document_serialize(handle: pointer; format: cint;
    destination: pointer; capacity: csize_t): csize_t =
  ensureRuntime()
  guard(csize_t(0)):
    let serialized = serializeDocument(documentOf(handle), formatFromC(format))
    writeBuffer(serialized.content, destination, capacity)

proc unitext_document_serialize_report(handle: pointer; format: cint;
    destination: pointer; capacity: csize_t): csize_t =
  ensureRuntime()
  guard(csize_t(0)):
    let serialized = serializeDocument(documentOf(handle), formatFromC(format))
    writeBuffer(conversionReportToString(serialized.content,
        serialized.diagnostics), destination, capacity)

proc unitext_convert(data: pointer; length: csize_t; sourceFormat,
    targetFormat: cint; destination: pointer; capacity: csize_t): csize_t =
  ensureRuntime()
  guard(csize_t(0)):
    let converted = convertDocument(inputString(data, length), formatFromC(
        sourceFormat),
      formatFromC(targetFormat))
    writeBuffer(converted.content, destination, capacity)

proc unitext_convert_report(data: pointer; length: csize_t;
    sourceFormat, targetFormat: cint; destination: pointer;
    capacity: csize_t): csize_t =
  ensureRuntime()
  guard(csize_t(0)):
    let converted = convertDocument(inputString(data, length), formatFromC(
        sourceFormat),
      formatFromC(targetFormat))
    writeBuffer(conversionReportToString(converted.content,
        converted.diagnostics),
      destination, capacity)

{.pop.}
