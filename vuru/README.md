# vuruV3

A **paru/yay-like** package manager for VUP (Void User Packages), written in [Odin](https://odin-lang.org).

## Features

- 🔍 **Unified Search** - Search VUP and official Void repos together
- 📦 **Dependency Resolution** - Automatically resolves and installs dependencies
- 🏗️ **Build from Source** - Build VUP packages locally via xbps-src
- 📋 **Template Review** - Review package templates before install (like paru)
- ⚡ **Transaction Planning** - See exactly what will be installed/built
- 🔄 **Smart Updates** - Update all VUP packages with one command

## Why Odin?

This is the third iteration of vuru, rewritten in Odin for:

- **Explicit memory management** with custom allocators
- **Predictable performance** without GC pauses
- **Better than C** ergonomics (defer, multiple returns, sum types)
- **Future-proof** for dependency resolution (complex graph algorithms)
- **Maintainable** by future developers

## Building

Make sure you have Odin installed. Then run:

```bash
make
```

For a debug build:

```bash
make debug
```

## Installation

```bash
sudo make install
```

## Usage

```
Usage: vuru [OPTIONS] [COMMAND] [ARGS...]

A paru/yay-like AUR helper for VUP (Void User Packages).

Commands:
  search, s  <query>    Search packages (VUP + official)
  install, i <pkgs...>  Install packages (resolves dependencies)
  remove, r  <pkgs...>  Remove packages
  update, u             Update all VUP packages
  query, q   <pkg>      Show package information
  build, b   <pkgs...>  Build packages from source
  clone                 Clone/update VUP repository

Options:
  -S, --sync       Force sync/refresh the package index
  -y, --yes        Assume yes to prompts
  -d, --deps       Show resolved dependencies (dry-run)
  -b, --build      Force build from source
  -a, --all        Search all repos (including official)
  --vup-only       Search VUP packages only
  -v, --version    Show version information
  -h, --help       Show this help message
```

## Examples

```bash
# Search for packages (VUP + official repos)
vuru search code

# Install a VUP package (resolves deps automatically)
vuru visual-studio-code

# Show what would be installed
vuru -d ferdium

# Force sync index and install
vuru -Sy vlang

# Build a package from source
vuru clone              # First time: clone VUP repo
vuru build odin         # Build odin locally

# Update all VUP packages
vuru update

# Query package info
vuru query visual-studio-code
```

Examples:
  vuru search editor           Search for packages
  vuru install visual-studio-code
  vuru -Sy install ferdium     Sync and install
  vuru update                  Update all packages
```

## Project Structure

```
vuruV3/
├── Makefile
├── README.md
├── build/
│   └── vuru
└── src/
    ├── main.odin        # CLI entry point, argument parsing
    ├── utils.odin       # Logging, file I/O, command execution
    ├── index.odin       # Package index loading/parsing
    ├── cache.odin       # Template caching
    ├── search.odin      # Package search
    ├── install.odin     # VUP install orchestration
    ├── uninstall.odin   # VUP uninstall orchestration
    ├── diff.odin        # Template diff and review
    ├── upgrade.odin     # VUP upgrade orchestration
    └── xbps/            # XBPS wrapper module
        ├── common.odin  # Shared utilities (arg building, parsing)
        ├── install.odin # xbps-install wrappers
        ├── query.odin   # xbps-query wrappers
        ├── remove.odin  # xbps-remove wrappers
        ├── upgrade.odin # xbps upgrade operations
        └── version.odin # xbps-uhelper version comparison
```

## Architecture

### Package Structure

- **`package main`** - Application logic (CLI, orchestration, caching)
- **`package xbps`** - Low-level XBPS command wrappers

The `xbps/` module isolates all direct XBPS interactions, making it easy to:
1. Test XBPS operations independently
2. Add new XBPS features without touching business logic
3. Eventually replace with native dependency resolution

### Design Principles

- **Dependency injection**: XBPS functions accept command runners as parameters
- **Single responsibility**: Each file has one clear purpose
- **No global state**: All state passed explicitly
- **Explicit errors**: No exceptions, all failures returned as values

## Memory Management

This implementation uses Odin's allocator system:

- `context.allocator` - Default allocator for long-lived data
- `context.temp_allocator` - Scratch allocator for temporary strings
- Explicit `defer delete()` for cleanup

This design makes it easy to:
1. Track memory ownership
2. Profile memory usage
3. Use arena allocators for performance-critical paths (future)

## Future: Dependency Resolution

The codebase is structured to support future dependency resolution:

```odin
// Future: Custom allocator for resolution graph
Resolver :: struct {
    arena:     mem.Arena,
    packages:  map[string]^Package_Node,
    // ...
}

resolve :: proc(r: ^Resolver, targets: []string) -> ([]string, bool) {
    // SAT-like resolution with explicit memory control
}
```

## Version History

- **vuru (C)** - Original implementation (~2000 LOC)
- **vuruV2 (V)** - First rewrite (~1050 LOC)
- **vuruV3 (Odin)** - Current version

## License

Same license as the original vuru project.
