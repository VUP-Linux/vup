# vuru v2

A package manager frontend for the VUP (Void User Packages) repository, rewritten in [Odin](https://odin-lang.org/).

## Building

### Requirements

- Odin compiler (latest) 
>Odin isn't on Void repo's but it does exist in VUP

```bash
vuru -S odin
```
- POSIX-compatible system (Linux)

### Compile

```bash
make           # Release build
make debug     # Debug build
make clean     # Clean build artifacts
```

### Install

```bash
sudo make install              # Install to /usr/local/bin
sudo make PREFIX=/usr install  # Install to /usr/bin
```

## Usage

```bash
vuru search <query>       # Search for packages
vuru install <pkg...>     # Install packages
vuru remove <pkg...>      # Remove packages
vuru update               # Update all VUP packages

# Options
vuru -S                   # Sync/refresh package index
vuru -Sy install <pkg>    # Sync and install
vuru -y install <pkg>     # Skip confirmation prompts
```

## Features

- **Template Review**: Shows package build templates before installation
- **Diff Display**: Shows changes to templates since last install
- **XDG Compliance**: Respects `XDG_CACHE_HOME` for cache storage
- **Security**: Validates package names and URLs to prevent injection

## Changes from v1 (C)

- Rewritten in Odin for better ergonomics and maintainability
- Native JSON parsing (no external cJSON dependency)
- Cleaner error handling with `or_return`
- ~50% less code while maintaining full functionality

## License

Same license as the original vuru.
