CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -Werror -std=c11
BIN ?= test_unitext
RUN ?= ./$(BIN)
RM_F ?= rm -f

all: $(BIN)
	$(RUN)

$(BIN): test_unitext.c ../../include/UniText.h ../../libUniText.a
	$(CC) $(CFLAGS) -I../../include -o $(BIN) test_unitext.c ../../libUniText.a

clean:
	$(RM_F) $(BIN)
