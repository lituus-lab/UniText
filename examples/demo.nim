# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import UniText

let source = "# Portable document\n\nText with **strong meaning**.\n"
echo convertDocument(source, formatMarkdown, formatAsciiDoc).content
