# Neutral document model

## Purpose

The model is a semantic interchange representation, not a universal syntax tree for every source
format. It must support conversion and editing without pretending that all source features are
portable.

## Initial block model

- document metadata;
- headings with explicit levels;
- paragraphs containing inline content;
- ordered and unordered lists;
- block quotations;
- fenced or literal code blocks with an optional language;
- thematic breaks;
- explicit format extensions for content that cannot yet be represented neutrally.

## Initial inline model

- text;
- emphasis and strong emphasis;
- inline code;
- links with a destination and optional title;
- hard and soft breaks;
- explicit format extensions.

Every node has a stable identifier inside a document value. Identifiers support selections,
incremental edits, diagnostics, and frontend projections without placing frontend state in the
model.

## Interchange contract

The canonical JSON interchange uses the `unitext.document` schema name and an explicit integer
version. It preserves node identifiers, semantic kinds, metadata, hierarchy, format extensions,
and link attributes. Readers reject unknown schema versions and invalid structures. This contract
is intended for process boundaries, fixtures, frontend adapters, and a future Lituus
implementation; it is not a persistence substitute for original source files.

Interchange schema version 2 carries the source span of the document and every block and inline
node. A span contains half-open UTF-8 byte offsets (`byte_start <= position < byte_end`) and
one-based line and byte-column coordinates. `null` is reserved for nodes created by a consumer or
by an edit without a direct source representation. Readers require the `span` member even when its
value is `null`, so an older producer cannot silently masquerade as a complete source-map producer.

## Separation of concerns

The semantic tree is immutable by construction. Node fields are private, sequence and metadata
inputs are defensively copied, and accessors return copies of mutable containers. Edits are explicit
operations that return a new document and a deterministic change record. Parsed source spans are
stored on the nodes; format-specific round-trip metadata remains side data keyed by node identifier.
Cursor positions, selections, layout boxes, viewport state, and collaboration presence are consumer
state.

## Loss contract

Parsing and serialization return diagnostics. A diagnostic records severity, code, message, source
location when known, and the affected node identifier. Unsupported content is either retained as an
explicit extension node or reported as a loss. Silent deletion is forbidden.

## Resource contract

Every parser receives limits for input bytes, nesting depth, total node count, and decoded text
bytes. Limit failures are errors, not partial successful parses.
