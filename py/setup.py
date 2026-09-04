# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Build the Cython extension over the UniText C ABI."""
import os
import shutil
import subprocess
import sys

from Cython.Build import cythonize
from setuptools import Extension, setup

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PACKAGE = os.path.join(HERE, "unitext")
VENDOR = os.path.join(HERE, "_nimsrc")
NIMBLE_FILE = "UniText.nimble"
IS_SDIST = "sdist" in sys.argv
NEEDS_LIBRARY = any(command in sys.argv for command in
                    ["build_ext", "bdist_wheel", "install", "develop"])

if sys.platform == "win32":
    LIBRARY, BUNDLED, LINK_ARGS, TASK = "UniText.lib", False, [], "clibMsvc"
elif sys.platform == "darwin":
    LIBRARY, BUNDLED, LINK_ARGS, TASK = (
        "libUniText.dylib", True, ["-Wl,-rpath,@loader_path"], "clib")
else:
    LIBRARY, BUNDLED, LINK_ARGS, TASK = (
        "libUniText.so", True, ["-Wl,-rpath,$ORIGIN"], "clib")


def vendor_nim_source():
    if os.path.exists(VENDOR):
        shutil.rmtree(VENDOR)
    os.makedirs(VENDOR)
    for filename in [NIMBLE_FILE, "config.nims"]:
        shutil.copy2(os.path.join(ROOT, filename), os.path.join(VENDOR, filename))
    for directory in ["src", "include"]:
        shutil.copytree(os.path.join(ROOT, directory), os.path.join(VENDOR, directory))


def project_directory():
    if os.path.exists(os.path.join(ROOT, NIMBLE_FILE)):
        return ROOT
    if os.path.exists(os.path.join(VENDOR, NIMBLE_FILE)):
        return VENDOR
    return None


def ensure_library():
    prebuilt = os.path.join(ROOT, LIBRARY)
    if os.path.exists(prebuilt):
        return prebuilt
    project = project_directory()
    if project is None:
        raise SystemExit("setup.py: UniText Nim sources are missing")
    try:
        # Through the gate, not bare: nimble exits 0 even when an `exec`
        # inside a task failed, so check_call would see a success that never
        # produced the library and the link would fail with something obscure.
        gate = os.path.join(project, "build",
                            "unigate.exe" if sys.platform == "win32" else "unigate")
        if not os.path.exists(gate):
            subprocess.check_call(
                ["nim", "c", "--hints:off", "-o:" + gate, "tools/gate.nim"],
                cwd=project)
        subprocess.check_call([gate, TASK], cwd=project)
    except (FileNotFoundError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"setup.py: unable to build UniText: {error}")
    built = os.path.join(project, LIBRARY)
    if not os.path.exists(built):
        raise SystemExit(f"setup.py: build did not produce {built}")
    return built


if IS_SDIST:
    vendor_nim_source()
    include_dir = os.path.join(ROOT, "include")
    library_dir = ROOT
elif NEEDS_LIBRARY:
    library = ensure_library()
    library_dir = os.path.dirname(library)
    include_dir = os.path.join(ROOT, "include")
    if not os.path.isdir(include_dir):
        include_dir = os.path.join(VENDOR, "include")
    if BUNDLED:
        os.makedirs(PACKAGE, exist_ok=True)
        shutil.copy2(library, os.path.join(PACKAGE, LIBRARY))
else:
    project = project_directory()
    library_dir = ROOT if project == ROOT else VENDOR
    include_dir = os.path.join(library_dir, "include")

pyx = os.path.join("unitext", "_core.pyx")
source = pyx if os.path.exists(os.path.join(HERE, pyx)) else os.path.join("unitext", "_core.c")
extension = Extension("unitext._core", [source], include_dirs=[include_dir],
                      library_dirs=[library_dir], libraries=["UniText"],
                      extra_link_args=LINK_ARGS)
modules = cythonize([extension], language_level=3) if source.endswith(".pyx") else [extension]

setup(ext_modules=modules, include_package_data=IS_SDIST,
      package_data={"unitext": [LIBRARY] if BUNDLED else []},
      zip_safe=False)
