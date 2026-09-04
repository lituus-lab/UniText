<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# Contributing

Contributions use Apache-2.0 and the Developer Certificate of Origin. Every commit must carry a
`Signed-off-by` trailer and follow Conventional Commits.

Run the complete local gate before review:

```sh
nimble testAll
nimble pyTest
nimble lint
nimble checkVGraph
nimble docs
```

Codec changes require representative success, malformed-input, resource-limit, conversion, and
loss-report fixtures. A new syntax feature must either map to the neutral model, survive as an
extension, or produce an explicit diagnostic. Silent deletion is not accepted.

C ABI changes update `include/UniText.h`, `src/UniText/c_api.nim`, C tests, the Cython binding, and
the Book together.
