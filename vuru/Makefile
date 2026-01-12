.PHONY: all build release debug clean install uninstall

PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

SRC_DIR := src
BUILD_DIR := build
TARGET := vuru

ODIN ?= odin

# Build flags
COMMON_FLAGS := -collection:src=$(SRC_DIR)

all: release

build: release

release:
	@mkdir -p $(BUILD_DIR)
	$(ODIN) build $(SRC_DIR) -out:$(BUILD_DIR)/$(TARGET) -o:speed $(COMMON_FLAGS)
	@echo "Built $(BUILD_DIR)/$(TARGET)"

debug:
	@mkdir -p $(BUILD_DIR)
	$(ODIN) build $(SRC_DIR) -out:$(BUILD_DIR)/$(TARGET) -debug $(COMMON_FLAGS)
	@echo "Built $(BUILD_DIR)/$(TARGET) (debug)"

clean:
	rm -rf $(BUILD_DIR)

install: release
	install -Dm755 $(BUILD_DIR)/$(TARGET) $(DESTDIR)$(BINDIR)/$(TARGET)

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(TARGET)

run: debug
	./$(BUILD_DIR)/$(TARGET) $(ARGS)

test: debug
	./$(BUILD_DIR)/$(TARGET) --help
	./$(BUILD_DIR)/$(TARGET) --version
