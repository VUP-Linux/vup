# Makefile for vuruV3 (Odin version)

ODIN = odin
ODIN_FLAGS = -o:speed
DEBUG_FLAGS = -debug -o:none

PREFIX ?= /usr/local
DESTDIR ?=

SRC_DIR = src
BUILD_DIR = build
TARGET = $(BUILD_DIR)/vuru

# Collections for package imports
COLLECTIONS = -collection:xbps=$(SRC_DIR)/xbps -collection:errors=$(SRC_DIR)/errors

.PHONY: all clean install uninstall debug run check

all: $(TARGET)

$(TARGET): $(SRC_DIR)/*.odin $(SRC_DIR)/xbps/*.odin $(SRC_DIR)/errors/*.odin
	@mkdir -p $(BUILD_DIR)
	$(ODIN) build $(SRC_DIR) -out:$@ $(ODIN_FLAGS) $(COLLECTIONS)

debug: $(SRC_DIR)/*.odin $(SRC_DIR)/xbps/*.odin $(SRC_DIR)/errors/*.odin
	@mkdir -p $(BUILD_DIR)
	$(ODIN) build $(SRC_DIR) -out:$(TARGET) $(DEBUG_FLAGS) $(COLLECTIONS)

check: $(SRC_DIR)/*.odin $(SRC_DIR)/xbps/*.odin $(SRC_DIR)/errors/*.odin
	$(ODIN) check $(SRC_DIR) $(COLLECTIONS)

run: $(TARGET)
	./$(TARGET) $(ARGS)

clean:
	rm -rf $(BUILD_DIR)

install: $(TARGET)
	install -Dm755 $(TARGET) $(DESTDIR)$(PREFIX)/bin/vuru

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/vuru
