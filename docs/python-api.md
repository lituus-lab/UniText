# Python API

The Python package is a thin Cython wrapper over the stable UniText C ABI. The document engine and
all codecs remain implemented in Nim.

```python
import unitext

document = unitext.parse(b"# Portable document\n", unitext.Format.MARKDOWN)
report = unitext.serialize_with_report(document, unitext.Format.RTF)
print(report["content"])
print(report["diagnostics"])
```

Inputs are bytes so callers control source decoding. `Document` owns a native handle and releases
it automatically. Edit methods return a new `Document`; they do not mutate the source document.
