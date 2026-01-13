# VUP – Void User Packages

Community package repository for Void Linux. Prebuilt `.xbps` packages, no compiling required.

**vuru** – A paru/yay-like package manager for VUP. Written in [Odin](https://odin-lang.org).

## Install

```bash
sudo xbps-install -R https://github.com/VUP-Linux/vup/releases/download/core-x86_64-current -S vuru
```

## Usage

```bash
vuru visual-studio-code    # Install package (implicit)
vuru search code           # Search VUP + official repos
vuru -Sy ferdium           # Sync index and install
vuru update                # Update all VUP packages
vuru remove <pkg>          # Remove package
vuru query <pkg>           # Show package info
vuru -d <pkg>              # Dry-run (show what would be installed)
```

## Features

### Unified Search
Search across VUP and official Void repos simultaneously:
```bash
vuru search editor
```
Results show source (`[VUP]` or `[void]`), installed status, and descriptions.

### Dependency Resolution
Automatically resolves dependencies across VUP and official repos:
```bash
vuru -d antigravity
# Shows: VUP packages to install, official deps, build order
```

### Template Review
Like paru, review package templates before installation:
```bash
vuru ferdium
# Shows template diff, prompts for confirmation
```

### Build from Source
Build VUP packages locally using xbps-src:
```bash
vuru clone              # Clone VUP repo to ~/.local/share/vup
vuru build odin         # Build package from source
```

### xbps-src Wrapper (`vuru src`)
**The killer feature.** Wraps `xbps-src` to automatically resolve VUP dependencies

Guide:

```bash
# Go into your cloned void-packages
cd ~/void-packages

# write a template that for e.g. 
hostmakedepends="vlang"

# Build it - vuru downloads VUP deps to hostdir/binpkgs automatically
vuru src pkg v-analyzer
```

What happens:
1. Parses template's `depends`, `makedepends`, `hostmakedepends`
2. Checks which deps exist in VUP index
3. Downloads `.xbps` files to `hostdir/binpkgs/`
4. Updates local repo with `xbps-rindex`
5. Runs `xbps-src pkg <package>`

This solves the "can't build locally because dep isn't in official repos" problem.

**Example:** Building a package that depends on `vlang` (VUP-only):
```
$ vuru src pkg v-analyzer
[info] Checking VUP dependencies for 'v-analyzer'...

:: VUP dependencies detected for 'v-analyzer':
   vlang (0.4.11_1)

[info] Downloading VUP dependencies to ./hostdir/binpkgs...
[info] Downloading vlang to hostdir/binpkgs...
[info] Updating local repository index...
index: added `vlang-0.4.11_1' (x86_64).
[info] Running: xbps-src pkg v-analyzer
=> v-analyzer-0.0.4_1: building for x86_64...
   [host] vlang: found (/host/binpkgs)
   ...
=> Creating v-analyzer-0.0.4_1.x86_64.xbps
```

## All Commands

| Command | Description |
|---------|-------------|
| `vuru <pkg>` | Install package (resolves deps) |
| `vuru search <query>` | Search VUP + official repos |
| `vuru remove <pkg>` | Remove package |
| `vuru update` | Update all VUP packages |
| `vuru query <pkg>` | Show package info |
| `vuru build <pkg>` | Build from source |
| `vuru clone` | Clone/update VUP repo |
| `vuru src <cmd> <pkg>` | xbps-src wrapper with VUP dep resolution |

## Flags

| Flag | Description |
|------|-------------|
| `-S, --sync` | Force sync package index |
| `-y, --yes` | Skip confirmations |
| `-d, --deps` | Show resolved deps (dry-run) |
| `-b, --build` | Force build from source |
| `--vup-only` | Search VUP packages only |

## How It Works

- **No servers** – GitHub Releases host all `.xbps` files
- **Native xbps** – Uses `xbps-install` under the hood
- **CI-built** – All packages built by GitHub Actions
- **Signed packages** – RSA signatures like official repos

## Contributing

Add packages via PR. See [CONTRIBUTING.md](CONTRIBUTING.md).

```
vup/srcpkgs/<category>/<pkgname>/template
```

## License

MIT
