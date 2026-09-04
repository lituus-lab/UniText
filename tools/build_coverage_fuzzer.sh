#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
set -eu

unitext_fuzz_cc="${UNITEXT_FUZZ_CC:-clang}"
unitext_sanitizers="${UNITEXT_FUZZ_SANITIZERS:-address,undefined}"
unitext_build_dir="${UNITEXT_FUZZ_BUILD_DIR:-build}"
unitext_cache_dir="${unitext_build_dir}/cache_fuzz_coverage"
unitext_library="${unitext_build_dir}/libUniTextFuzz.a"
unitext_target="${unitext_build_dir}/fuzz_unitext"

case "$(uname -s)" in
  Darwin|Linux) ;;
  *)
    echo "ERROR: coverage-guided fuzzing currently requires Darwin or Linux" >&2
    exit 2
    ;;
esac

command -v nim >/dev/null 2>&1 || {
  echo "ERROR: Nim is required" >&2
  exit 2
}
command -v "${unitext_fuzz_cc}" >/dev/null 2>&1 || {
  echo "ERROR: ${unitext_fuzz_cc} is required" >&2
  exit 2
}

mkdir -p "${unitext_build_dir}"
nim c --cc:clang --path:src --nimcache:"${unitext_cache_dir}" \
  --app:staticlib -d:noAutoInit --noMain --mm:arc -d:release \
  --passC:"-fsanitize=fuzzer-no-link,${unitext_sanitizers}" \
  --hints:off -o:"${unitext_library}" src/UniText/c_api.nim

"${unitext_fuzz_cc}" -std=c11 -g -O1 -Wall -Wextra -Werror \
  -fsanitize="fuzzer,${unitext_sanitizers}" -Iinclude \
  tests/fuzz/fuzz_unitext.c "${unitext_library}" -o "${unitext_target}"

echo "coverage fuzzer built: ${unitext_target}"
