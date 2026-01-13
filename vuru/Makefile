# Makefile for vuru (Odin version)

ODIN = odin
ODIN_FLAGS = -o:speed
DEBUG_FLAGS = -debug -o:none

PREFIX ?= /usr/local
DESTDIR ?=

SRC_DIR = src
BUILD_DIR = build
TARGET = $(BUILD_DIR)/vuru

# Collections for package imports
COLLECTIONS = -collection:xbps=$(SRC_DIR)/core/xbps -collection:errors=$(SRC_DIR)/core/errors

# Find all .odin source files
SRCS = $(shell find $(SRC_DIR) -name '*.odin')

.PHONY: all clean install uninstall debug run check

all: $(TARGET)

$(TARGET): $(SRCS)
	@mkdir -p $(BUILD_DIR)
	$(ODIN) build $(SRC_DIR) -out:$@ $(ODIN_FLAGS) $(COLLECTIONS)

debug: $(SRCS)
	@mkdir -p $(BUILD_DIR)
	$(ODIN) build $(SRC_DIR) -out:$(TARGET) $(DEBUG_FLAGS) $(COLLECTIONS)

check: $(SRCS)
	$(ODIN) check $(SRC_DIR) $(COLLECTIONS)

run: $(TARGET)
	./$(TARGET) $(ARGS)

clean:
	rm -rf $(BUILD_DIR)

install: $(TARGET)
	install -Dm755 $(TARGET) $(DESTDIR)$(PREFIX)/bin/vuru

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/vuru
