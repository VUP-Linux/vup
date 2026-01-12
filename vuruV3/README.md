# vuruV3

A package manager frontend for VUP repository, written in [Odin](https://odin-lang.org).

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

To check for errors without building:

```bash
make check
```

## Installation

```bash
sudo make install
```

## Usage

```
Usage: vuru [OPTIONS] [COMMAND] [ARGS...]

A package manager frontend for VUP repository.

Commands:
  search  <query>     Search for packages
  install <pkgs...>   Install one or more packages
  remove  <pkgs...>   Remove one or more packages
  update              Update all installed packages

Options:
  -S, --sync          Force sync/refresh the package index
  -u, --update        Update all packages
  -y, --yes           Assume yes to prompts
  -v, --version       Show version information
  -h, --help          Show this help message

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
