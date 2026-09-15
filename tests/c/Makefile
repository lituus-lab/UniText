# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
# Shell-free: `pwd` and `rm` are unavailable under mingw32-make on Windows.
ifeq ($(origin CC),default)
  ifeq ($(OS),Windows_NT)
    CC := gcc
  else
    CC := cc
  endif
endif

ROOT   := $(CURDIR)/../..
# EXTRA_CFLAGS is a hook, not a knob: `nimble coverage` passes --coverage
# through it. Replacing CFLAGS from the command line would drop the include
# path, and here or in a sibling the -D the test needs.
CFLAGS := -I$(ROOT)/include -O2 -Wall -Wextra -std=c11 $(EXTRA_CFLAGS)
LIB    := $(ROOT)/libUniText.a

ifeq ($(OS),Windows_NT)
  BIN  := test_unitext.exe
  RUN  := $(BIN)
  RM_F := del /q
else
  BIN  := test_unitext
  RUN  := ./$(BIN)
  RM_F := rm -f
endif

.PHONY: all run clean
all: run
run: $(BIN)
	$(RUN)
$(BIN): test_unitext.c $(ROOT)/include/UniText.h $(LIB)
	$(CC) $(CFLAGS) -o $(BIN) test_unitext.c $(LIB)
# File target, not phony: `nimble ctest` already built the lib, don't redo it.
$(LIB):
	cd $(ROOT) && nimble clibStatic
clean:
	$(RM_F) $(BIN)
