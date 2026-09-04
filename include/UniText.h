// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
#ifndef UNITEXT_H
#define UNITEXT_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define UNITEXT_VERSION_MAJOR 0
#define UNITEXT_VERSION_MINOR 1
#define UNITEXT_VERSION_PATCH 0
#define UNITEXT_VERSION "0.1.0"

#define UNITEXT_VERSION_AT_LEAST(ma, mi, pa) \
  ((UNITEXT_VERSION_MAJOR > (ma)) || \
   (UNITEXT_VERSION_MAJOR == (ma) && UNITEXT_VERSION_MINOR > (mi)) || \
   (UNITEXT_VERSION_MAJOR == (ma) && UNITEXT_VERSION_MINOR == (mi) && \
    UNITEXT_VERSION_PATCH >= (pa)))

/* Largest n with unitext_fibonacci(n) fitting in long long (int64). */
#define UNITEXT_FIB_MAX_N 92

/* Static version string; do not free. */
const char *unitext_version(void);

/* fibonacci(n), n clamped to [0, UNITEXT_FIB_MAX_N].
 * n < 0 -> 0; n > UNITEXT_FIB_MAX_N -> fibonacci(UNITEXT_FIB_MAX_N).
 * Never raises. Single-threaded, reentrant. */
long long unitext_fibonacci(int n);

#ifdef __cplusplus
}
#endif

#endif /* UNITEXT_H */
