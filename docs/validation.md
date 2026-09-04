# Validation status

## Version 0.2.0 validation

Status: passed locally on macOS arm64.

- Equivalent Markdown, reStructuredText, AsciiDoc, and styled RTF fixtures produce one common
  block-level semantic snapshot.
- Markdown, reStructuredText, and AsciiDoc preserve the portable strong, emphasis, inline-code,
  and hyperlink intersection in both directions.
- Format detection combines bounded content inspection with optional filename evidence.
- Every format has an explicit capability descriptor.
- Every format supports the initial heading, paragraph, unordered-list, and code-block subset in
  both parsing and serialization.
- Cross-format conversion propagates parsing and serialization diagnostics.
- Stable node identifiers support immutable text replacement with a deterministic change record.
- AST fields are opaque and container inputs/outputs are defensively copied; compile-time tests
  reject direct mutation and runtime tests reject malformed UTF-8 throughout the model.
- Every document, block, and inline parsed by all four codecs carries a half-open byte span and
  one-based line/byte-column coordinates. CR, LF, CRLF, and multibyte UTF-8 offsets are tested.
- The versioned JSON interchange round-trips identifiers, hierarchy, metadata, inline semantics,
  extension payloads, and source spans, and rejects unknown or malformed structures.
- Input bytes, nesting, node count, and decoded text have explicit limits.
- Malformed delimiters, unknown formats, missing RTF signatures, and invalid edit targets fail
  explicitly.
- A pinned 23-case official projection covers CommonMark 0.31.2, Docutils 0.23, the Eclipse
  AsciiDoc TCK, and independently authored Microsoft RTF 1.9.1 vectors. Twenty-two cases are also
  compared with Pandoc 3.10.2; the one explicit exclusion records Pandoc's RTF surrogate behavior.
- A 5,000-mutation smoke gate runs on every CI change. A weekly ASan/UBSan job runs a fixed
  100,000-case regression seed and a rotating 500,000-case seed, logging enough data to replay a
  failure exactly.

## Intentional limitations

- The RTF parser currently normalizes character styling. Its serializer emits strong and emphasis
  controls but reports inline-code and hyperlink destination loss explicitly.
- Escapes and deeply nested delimiter edge cases remain outside the lightweight-format subset.
- RTF parsing is a safe styled subset, not a complete RTF 1.9 implementation.
- Tables, images, footnotes, directives, fields, comments, tracked changes, sections, page styles,
  and embedded objects are not implemented.
- Source maps describe the syntax consumed by each semantic node; they do not yet preserve every
  discarded delimiter as a separate concrete-syntax token. Format-specific lossless round-trip
  metadata remains future work.
- Streaming is a declared future capability, not currently advertised by a codec.
- No CLI, editor, layout engine, renderer, collaboration layer, or frontend is included.
- No existing consumer has been modified.

Version 0.2.0 validates the documented neutral model, interchange schema version 2, C ABI version
1, and the explicitly supported codec subsets without making a stable-API promise. It does not
claim full compatibility with every feature of the source formats. Publication remains a separate,
deliberate action.
