# Makefile for vuru (Odin version)

ODIN = odin
ODIN_FLAGS = -o:speed -reloc-mode:pic -extra-linker-flags="-pie"
DEBUG_FLAGS = -debug -o:none

# Cross-compilation support for xbps-src
# XBPS_TARGET_MACHINE is set by xbps-src when cross-compiling
ifdef XBPS_TARGET_MACHINE
  ifeq ($(XBPS_TARGET_MACHINE),aarch64)
    ODIN_TARGET = -target:linux_arm64
    # Use the cross-linker provided by xbps-src
    ifdef LD
      ODIN_FLAGS += -extra-linker-flags="-fuse-ld=$(LD)"
    endif
  else ifeq ($(XBPS_TARGET_MACHINE),x86_64)
    ODIN_TARGET = -target:linux_amd64
  endif
endif

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

all: clean $(TARGET)

$(TARGET): $(SRCS)
	@mkdir -p $(BUILD_DIR)
	$(ODIN) build $(SRC_DIR) -out:$@ $(ODIN_FLAGS) $(ODIN_TARGET) $(COLLECTIONS)

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
