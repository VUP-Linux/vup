CC = gcc
CFLAGS = -Wall -Wextra -O2 -I./src
LDFLAGS = 

PREFIX ?= /usr/local
DESTDIR ?=

SRC_DIR = src
OBJ_DIR = obj
BIN_DIR = .

SRCS = $(wildcard $(SRC_DIR)/*.c) $(wildcard $(SRC_DIR)/xbps/*.c) $(wildcard $(SRC_DIR)/vendor/*.c)
OBJS = $(patsubst $(SRC_DIR)/%.c, $(OBJ_DIR)/%.o, $(SRCS))
TARGET = $(BIN_DIR)/vuru

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(OBJS) -o $@ $(LDFLAGS)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -rf $(OBJ_DIR) $(TARGET)

install: $(TARGET)
	install -Dm755 $(TARGET) $(DESTDIR)$(PREFIX)/bin/vuru

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/vuru

.PHONY: all clean install uninstall
