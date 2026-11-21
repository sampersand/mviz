CC     ?= cc
CFLAGS ?= -Wall -Wextra -g
TARGET = mviz

SRCS = $(wildcard *.c)
OBJS = $(SRCS:.c=.o)

run: $(TARGET)
	@-env NO_COLOR=1 ./mviz "$(shell printf 'hello\tworld')👍"

# Link all object files into the final executable
$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^

# Compile each .c file into a matching .o file
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

# Remove build artifacts
clean:
	rm -f $(OBJS) $(TARGET)

.PHONY: clean run
