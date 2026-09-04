## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import UniText/[detect, model]

type
  CodecCapability* = enum
    capabilityParse
    capabilitySerialize
    capabilityRoundTripMetadata
    capabilityStreaming

  CodecInfo* = object
    format*: TextFormat
    name*: string
    capabilities*: set[CodecCapability]
    supportedBlocks*: set[BlockKind]
    supportedInlines*: set[InlineKind]

  ParseResult* = object
    document*: Document
    diagnostics*: seq[Diagnostic]

  SerializeResult* = object
    content*: string
    diagnostics*: seq[Diagnostic]

  CodecError* = object of ValueError

proc diagnostic*(severity: DiagnosticSeverity; code, message: string;
    nodeId = ""): Diagnostic =
  Diagnostic(severity: severity, code: code, message: message,
    nodeId: nodeId.nodeId)

proc emptyDocument*(): Document =
  newDocument()
