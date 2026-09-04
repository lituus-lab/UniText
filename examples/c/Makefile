CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -Werror -std=c11
BIN ?= demo
RUN ?= ./$(BIN)
RM_F ?= rm -f
all: $(BIN)
	$(RUN)
$(BIN): demo.c ../../include/UniText.h ../../libUniText.a
	$(CC) $(CFLAGS) -I../../include -o $(BIN) demo.c ../../libUniText.a
clean:
	$(RM_F) $(BIN)
