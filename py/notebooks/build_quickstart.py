# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Create and execute the committed UniText quickstart notebook."""
from pathlib import Path

import nbformat
from nbclient import NotebookClient


notebook = nbformat.v4.new_notebook()
notebook["metadata"]["kernelspec"] = {
    "display_name": "Python 3",
    "language": "python",
    "name": "python3",
}
notebook["cells"] = [
    nbformat.v4.new_markdown_cell(
        "# UniText quickstart\n\n"
        "This notebook exercises the installed Cython binding over the C ABI."
    ),
    nbformat.v4.new_code_cell(
        "import unitext\n"
        "print(unitext.version())"
    ),
    nbformat.v4.new_code_cell(
        "source = b'# Portable document\\n\\nText with **strong meaning**.\\n'\n"
        "print(unitext.detect(source, 'sample.md'))\n"
        "print(unitext.convert(source, unitext.Format.MARKDOWN, "
        "unitext.Format.ASCIIDOC).decode())"
    ),
    nbformat.v4.new_code_cell(
        "document = unitext.parse(source, unitext.Format.MARKDOWN)\n"
        "print(unitext.diagnostics(document))\n"
        "print(document.to_json().decode()[:47])"
    ),
]

NotebookClient(notebook, timeout=60, kernel_name="python3").execute()
destination = Path(__file__).with_name("quickstart.ipynb")
nbformat.write(notebook, destination)
print(destination)
