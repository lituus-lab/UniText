## SPDX-License-Identifier: Apache-2.0
## Copyright 2026 lituus-lab
import std/[json, os, sequtils, strutils]
import UniText

type DeterministicRng = object
  state: uint64

const FuzzLimits = ParseLimits(maxInputBytes: 8 * 1024,
  maxNestingDepth: 32, maxNodes: 20_000, maxDecodedBytes: 64 * 1024)

proc next(rng: var DeterministicRng): uint64 =
  var value = rng.state
  value = value xor (value shl 13)
  value = value xor (value shr 7)
  value = value xor (value shl 17)
  rng.state = value
  value

proc choose(rng: var DeterministicRng; limit: int): int =
  if limit <= 0: 0 else: int(rng.next mod uint64(limit))

proc formatOf(value: string): TextFormat =
  case value
  of "markdown": formatMarkdown
  of "rst": formatRestructuredText
  of "asciidoc": formatAsciiDoc
  of "rtf": formatRtf
  else: raise newException(ValueError, "unsupported corpus format: " & value)

proc sourceMapsComplete(document: Document): bool =
  if not document.span.isKnown:
    return false
  proc inlineComplete(node: InlineNode): bool =
    node.span.isKnown and node.children.allIt(it.inlineComplete)
  proc blockComplete(node: BlockNode): bool =
    node.span.isKnown and node.inlines.allIt(it.inlineComplete) and
      node.blocks.allIt(it.blockComplete)
  document.blocks.allIt(it.blockComplete)

proc prefix(value: string; length: int): string =
  if length <= 0: "" else: value[0 ..< min(length, value.len)]

proc suffix(value: string; first: int): string =
  if first >= value.len: "" else: value[max(first, 0) ..< value.len]

proc mutate(source: string; rng: var DeterministicRng): string =
  const tokens = ["\0", "\r", "\n", "\\", "{", "}", "[", "]", "(", ")",
    "*", "_", "`", "#", "-", "=", "~", "\x7f", "é", "😀"]
  result = source
  case rng.choose(8)
  of 0:
    if result.len > 0:
      let position = rng.choose(result.len)
      result[position] = char(ord(result[position]) xor (1 shl rng.choose(8)))
  of 1:
    let position = rng.choose(result.len + 1)
    result = result.prefix(position) & tokens[rng.choose(tokens.len)] &
      result.suffix(position)
  of 2:
    if result.len > 0:
      let first = rng.choose(result.len)
      let past = first + 1 + rng.choose(result.len - first)
      result = result.prefix(first) & result.suffix(past)
  of 3:
    if result.len > 0:
      let first = rng.choose(result.len)
      let past = first + 1 + rng.choose(result.len - first)
      let position = rng.choose(result.len + 1)
      result = result.prefix(position) & result[first ..< past] &
        result.suffix(position)
  of 4:
    let position = rng.choose(result.len + 1)
    let token = tokens[rng.choose(tokens.len)]
    result = result.prefix(position) & token.repeat(1 + rng.choose(32)) &
      result.suffix(position)
  of 5:
    result.setLen(rng.choose(result.len + 1))
  of 6:
    if result.len > 0:
      let position = rng.choose(result.len)
      result[position] = char(rng.choose(256))
  else:
    result = tokens[rng.choose(tokens.len)] & result &
      tokens[rng.choose(tokens.len)]
  if result.len > FuzzLimits.maxInputBytes:
    result.setLen(FuzzLimits.maxInputBytes)

proc exercise(content: string; format: TextFormat) =
  var parsed: ParseResult
  try:
    parsed = parseDocument(content, format, limits = FuzzLimits)
  except CodecError, ModelError:
    return
  parsed.document.validate(FuzzLimits)
  if not parsed.document.sourceMapsComplete:
    raise newException(ModelError, "successful parse has an incomplete source map")

  let interchange = parsed.document.toInterchangeString
  let restored = fromInterchangeString(interchange, FuzzLimits)
  restored.validate(FuzzLimits)

  for target in [formatMarkdown, formatRestructuredText, formatAsciiDoc,
      formatRtf]:
    let serialized = serializeDocument(restored, target).content
    if serialized.len > FuzzLimits.maxDecodedBytes:
      raise newException(CodecError, "serializer exceeded the fuzz output bound")
    var reparsed: Document
    try:
      reparsed = parseDocument(serialized, target, limits = FuzzLimits).document
    except CatchableError as error:
      raise newException(CodecError, "self-round-trip failed for " & $target &
        "; output_hex=" & serialized.toHex & "; cause=" & error.msg)
    reparsed.validate(FuzzLimits)
    if not reparsed.sourceMapsComplete:
      raise newException(ModelError, "serialized parse has an incomplete source map")

proc option(name: string; fallback: int): int =
  let prefix = "--" & name & "="
  result = fallback
  for argument in commandLineParams():
    if argument.startsWith(prefix):
      result = parseInt(argument[prefix.len .. ^1])

proc main() =
  let iterations = option("iterations", 5_000)
  let seed = option("seed", 0x5EED_2026)
  if iterations < 1 or iterations > 10_000_000:
    raise newException(ValueError, "iterations must be in 1..10000000")
  if seed < 1:
    raise newException(ValueError, "seed must be positive")
  var rng = DeterministicRng(state: uint64(seed))
  let corpusPath = currentSourcePath.parentDir.parentDir / "fixtures" /
    "official" / "cases-v1.json"
  let cases = parseFile(corpusPath)["cases"]
  for iteration in 0 ..< iterations:
    let fixture = cases[rng.choose(cases.len)]
    var content = fixture["input"].getStr
    for mutation in 0 .. rng.choose(4):
      content = content.mutate(rng)
    try:
      content.exercise(fixture["format"].getStr.formatOf)
    except Exception as error:
      stderr.writeLine("fuzz failure: seed=", seed, " iteration=", iteration,
        " case=", fixture["id"].getStr, " bytes=", content.len,
        " input_hex=", content.toHex, " error=", error.msg)
      raise
  stdout.writeLine("codec fuzz: ", iterations, " mutations passed; seed=", seed)

when isMainModule:
  main()
