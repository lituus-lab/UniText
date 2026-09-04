# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import pytest
import unitext


def test_version():
    assert unitext.version() == "0.1.0"
    assert unitext.__version__ == "0.1.0"


@pytest.mark.parametrize("n,want", [
    (0, 0), (1, 1), (2, 1), (10, 55), (20, 6765),
    (50, 12586269025),
])
def test_known_values(n, want):
    assert unitext.fibonacci(n) == want


def test_the_bound_comes_from_the_c_header():
    # Not a literal: the binding reads UNITEXT_FIB_MAX_N, so the value a
    # caller is checked against is the one the C ABI clamps to.
    assert unitext.FIB_MAX_N == 92
    assert unitext.fibonacci(unitext.FIB_MAX_N) == 7540113804746346429


def test_out_of_range_raises():
    with pytest.raises(ValueError):
        unitext.fibonacci(-1)
    with pytest.raises(ValueError):
        unitext.fibonacci(unitext.FIB_MAX_N + 1)


def test_non_int_raises():
    with pytest.raises(TypeError):
        unitext.fibonacci(10.0)
