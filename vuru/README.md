# vuru

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

Make sure you have Odin installed. Vuru is currently checked against
`dev-2026-07a`. Then run:

```bash
make
```

For a debug build:

```bash
make debug
```

## Installation

From the `vuru` directory, install the executable:

```bash
sudo make install
```

Then launch Vuru as your regular user to choose your default install mode:

```bash
vuru
```

The first interactive launch asks whether to build VUP packages locally and
saves your choice. Answer `y` for local builds or press Enter for prebuilt packages.

## Quick start

```bash
vuru search cstow          # Find a package
vuru install cstow         # Install using your saved default
vuru query cstow           # Show package information
vuru remove cstow          # Remove a package
vuru update               # Update VUP packages
```

Run `vuru --help` for the complete command and option list.

## Configuration

Edit `~/.config/vuru/config.conf` to change your default. If `XDG_CONFIG_HOME`
is set to an absolute path, the file is `$XDG_CONFIG_HOME/vuru/config.conf` instead.

```conf
# true: compile VUP packages locally; false: use prebuilt packages
build_local = true
```

Set `build_local = false` to switch back to prebuilt packages. Save the file;
Vuru reads it on the next launch. The file supports this boolean setting, blank
lines and `#` comments. Duplicate keys or invalid values produce an error.

Help/version requests, noninteractive runs, `--yes` and `--dry-run` skip first-run
setup. You can create the config manually in these cases. A missing or empty
config defaults to prebuilt packages. This setting applies to `install`/`i`;
`update`/`upgrade`/`u` uses it for VUP package updates. Official Void system
updates always use binary repositories.

## Install flags

```bash
vuru install cstow --build     # Download templates, compile and install locally
vuru install cstow --prebuilt  # Install the published prebuilt package
vuru install cstow --dry-run   # Preview the operation
vuru install cstow --yes       # Skip confirmations
vuru update --build            # Build available VUP updates locally
vuru update --prebuilt         # Use published packages for VUP updates
```

`--build` and `--prebuilt` override the config for one invocation without changing
your saved default. They cannot be combined. `-b` and `--local` alias `--build`;
`--package` aliases `--prebuilt`.

### Security model for build mode

`--build` applies to the complete VUP dependency chain. Vuru builds the requested
VUP package and every transitive VUP-only dependency from the templates in the
local VUP checkout. It does not silently replace those dependencies with packages
from VUP's published binary repositories.

Dependencies available from the official Void repositories are installed as
official prebuilt packages. This keeps the normal Void trust boundary for system
libraries and build tools—the same repositories used to install and update Void
Linux—while applying the stricter local-build choice to community VUP packages.

A VUP template can compile source code or package an upstream-provided binary.
Build mode follows the template and verifies declared distfile checksums; it does
not guarantee that every upstream artifact was compiled from source. Security
conscious users should review the requested package and dependency templates in
the checkout before proceeding. Use `--dry-run` to inspect the planned dependency
chain without downloading, building or installing packages.

Local installs download the VUP checkout to `~/.local/share/vup` if no existing
build tree is found, including templates, patches and build helpers. After
confirmation, Vuru bootstraps `xbps-src`, builds the requested VUP packages and
installs them from the local repositories. This needs Git, network access, disk
space and the usual xbps-src host prerequisites. Local mode uses each template's
upstream downloads, whether those are source archives or upstream binaries.

Each VUP-only dependency is built once per build invocation. Build-only
dependencies stay in the build environment; runtime dependencies are also
installed on the host. The build tree must include Vuru's local dependency
support, so update older checkouts with `vuru clone`.

Transaction summaries mark requested packages as `[explicit]` and resolved
runtime requirements as `[dependency]`. If a local dependency fails, Vuru stops
the parent build and prints the complete dependency chain ending at the failed
package.

To update your downloaded templates and build helpers:

```bash
vuru clone
```

Dry runs do not clone, build or install packages.

## Development checks

Run `make check` for Odin vet checks and `make test` for isolated CLI regression
tests. The tests mock network, XBPS and build commands and exercise first-run
setup through a pseudo-terminal; they do not install anything on the host.

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

- **vuru (C)** - Original implementation
- **vuru (Odin)** - Current version

## License

Same license as the original vuru project.
