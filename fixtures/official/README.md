# Official and differential corpus provenance

`cases-v1.json` contains a deliberately selected projection of upstream cases that fall inside
UniText's advertised 0.2 subset. It is not a claim of full CommonMark, reStructuredText, AsciiDoc,
or RTF conformance.

- CommonMark cases retain their official example number and are copied from tag 0.31.2 at commit
  `9103e341a973013013bb1a80e13567007c5cef6f` (BSD-2-Clause).
- reStructuredText cases retain the category/index from the Docutils 0.23 parser tests. The source
  distribution SHA-256 is
  `746f5060322511280a1e50eb76846ed6bf2342984b2ac04dc42caa1a8d78799e`; the selected test modules
  declare their cases public domain.
- AsciiDoc cases retain the Eclipse TCK fixture name from commit
  `cdfada9c2768b164eadf4bc12e9f9c68e6caf68a` (EPL-2.0). UniText compares only its neutral-model
  projection, not the full official ASG and does not claim TCK certification.
- The RTF vector is independently authored from the Unicode control-word rules in Microsoft RTF
  1.9.1. The specification is authoritative; the local vector is not a Microsoft conformance test.

The executable corpus gate validates source-map completeness, neutral block kinds, and semantic
plain text. `tools/differential_corpus.py` additionally compares the cases with Pandoc 3.10.2.
An oracle disagreement fails with the exact case identifier; it is never silently relabeled as an
expected result. The Unicode-surrogate RTF vector is explicitly excluded from the Pandoc comparison
because that pinned version emits replacement characters for it. The exclusion and reason live in
the machine-readable case; UniText still tests the authoritative expected value directly.
