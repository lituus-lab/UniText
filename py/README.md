<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# UniText for Python

The Python package is a Cython binding over the UniText C ABI, which is `0.x`
and not frozen. It exposes detection, parsing, versioned JSON interchange,
serialization, and conversion without reimplementing codecs.

```python
from unitext import Format, convert

source = b"# Portable document\n"
print(convert(source, Format.MARKDOWN, Format.ASCIIDOC).decode())
```
