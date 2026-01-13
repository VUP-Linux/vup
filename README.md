# VUP – Void User Packages

Community package repository for Void Linux. Prebuilt `.xbps` packages, no compiling required.

**vuru** is a package manager for VUP, similar to paru/yay for the AUR. Written in [Odin](https://odin-lang.org).

## Install

```bash
sudo xbps-install -R https://github.com/VUP-Linux/vup/releases/download/core-x86_64-current -S vuru
```

## Quick Start

```bash
vuru search code           # search VUP + official repos
vuru install vlang         # install a package
vuru install -Su           # Sync && update
vuru remove vlang          # Remove vlang
vuru remove -o             # remove orphan packages
vuru query odin            # show package details (template)
```

## Commands

```
vuru <command> [options] [arguments]

Commands:
  install  <pkg...>      Install packages (VUP + official)
  remove   <pkg...>      Remove packages
  update                 Update all packages
  build    <pkg...>      Build from source
  sync                   Sync repository index
  query    <pkg>         Show package info (or use modes below)
  fetch    <url...>      Download files from URLs
  clone                  Clone VUP repo locally
  src      <cmd> [args]  xbps-src wrapper
  help                   Show help

Query modes:
  -l, --list       List installed packages
  -f, --files      Show package files
  -x, --deps       Show dependencies
  --ownedby        Find package owning a file

Install/Remove flags:
  -S, --sync         Sync repos before operation
  -u, --update       Update mode (system upgrade)
  -R, --recursive    Recursive remove/deps
  -o, --orphans      Remove orphan packages
  -O, --clean-cache  Clean package cache

General options:
  -y, --yes        Skip confirmations
  -n, --dry-run    Show what would be done
  -b, --build      Force build from source
  -d, --desc       Include descriptions in search
  -v, --verbose    Verbose output
  -r, --rootdir    Alternate root directory
  --vup-only       VUP packages only

Aliases: q=query, s=search, i=install, r=remove, u=update
```

## Unified Search

Searches VUP and official Void repos at the same time:

```
$ vuru query -s zig

==> VUP Packages (1)
NAME          VERSION    CATEGORY     DESCRIPTION
zig15         0.15.2_1   programming  [installed]

==> Official Void Packages (2)
NAME          VERSION    DESCRIPTION
zig           0.13.0_1   Programming language...
zls           0.13.0_1   Zig language server
```

## Dependency Resolution

Resolves dependencies across VUP and official repos automatically:

```
$ vuru install -n antigravity

VUP packages (2):
  vlang antigravity

Official deps (3):
  libX11 libGL ...
```

## Build from Source

Build VUP packages locally:

```bash
vuru clone              # clone VUP repo to ~/.local/share/vup
vuru build odin         # build package from source
```

## xbps-src Wrapper

This is the main reason vuru exists. If you're writing a template that depends on a VUP package (like vlang), you can't build it with plain xbps-src because the dependency isn't in official repos.

`vuru src` fixes this:

```bash
cd ~/void-packages

# your template has: hostmakedepends="vlang"
vuru src pkg v-analyzer
```

What happens:
1. Parses template's `depends`, `makedepends`, `hostmakedepends`
2. Finds which deps are in VUP
3. Downloads those `.xbps` files to `hostdir/binpkgs/`
4. Runs `xbps-rindex` to update local repo
5. Runs `xbps-src pkg <package>`

Now xbps-src can find the VUP dependency and the build works.

```
$ vuru src pkg v-analyzer
[info] Checking VUP dependencies for 'v-analyzer'...

:: VUP dependencies detected for 'v-analyzer':
   vlang (0.4.11_1)

[info] Downloading vlang to hostdir/binpkgs...
[info] Updating local repository index...
index: added `vlang-0.4.11_1' (x86_64).
[info] Running: xbps-src pkg v-analyzer
=> v-analyzer-0.0.4_1: building for x86_64...
   [host] vlang: found (/host/binpkgs)
   ...
=> Creating v-analyzer-0.0.4_1.x86_64.xbps
```

## How It Works

- GitHub Releases host all `.xbps` files (no servers needed)
- Uses `xbps-install` under the hood
- Packages built by GitHub Actions
- RSA signed like official repos

## Contributing

Add packages via PR. See [CONTRIBUTING.md](CONTRIBUTING.md).

```
vup/srcpkgs/<category>/<pkgname>/template
```

## License

MIT
