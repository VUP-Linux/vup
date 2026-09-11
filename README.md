# VUP – Void User Packages

Community package repository for Void Linux, with prebuilt `.xbps` packages and
optional local builds from VUP templates.

**vuru** is a package manager for VUP, similar to paru/yay for the AUR. Written in [Odin](https://odin-lang.org).

See the [Vuru README](vuru/README.md) for build instructions, configuration,
install modes, and dependency behavior.

## Install

```bash
sudo xbps-install -R https://github.com/VUP-Linux/vup/releases/download/core-x86_64-current -S vuru
```

Launch Vuru once as your regular user to choose whether VUP packages should be
built locally or installed from the prebuilt repositories:

```bash
vuru
```

Press `y` to make local builds the default, or press Enter to use prebuilt
packages. Vuru saves the choice in `~/.config/vuru/config.conf`.

## Quick Start

```bash
vuru search cstow          # search VUP and official repositories
vuru install cstow         # install using the saved default
vuru query cstow           # show package information
vuru remove cstow          # remove a package
vuru update                # update installed packages
```

Run `vuru --help` for the complete command and option list.

## Configuration

Edit `~/.config/vuru/config.conf` to change the default install mode:

```conf
# true: build VUP packages locally; false: use prebuilt packages
build_local = true
```

When `XDG_CONFIG_HOME` is set to an absolute path, Vuru uses
`$XDG_CONFIG_HOME/vuru/config.conf` instead. The setting applies to VUP package
installs and updates. Official Void system updates always use Void's binary
repositories.

Use command-line flags to override the saved default for one invocation:

```bash
vuru install cstow --build     # build VUP packages locally
vuru install cstow --prebuilt  # install published VUP packages
vuru install cstow --dry-run   # preview the transaction
vuru update --build            # build available VUP updates locally
vuru update --prebuilt         # use published packages for VUP updates
```

`--build` and `--prebuilt` cannot be combined. `-b` and `--local` are aliases
for `--build`; `--package` is an alias for `--prebuilt`.

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

Resolves dependencies across VUP and official repositories automatically:

```
$ vuru install v-analyzer --build --dry-run

Build from source (2):
  v-analyzer-0.0.4_1 [explicit]
  vlang-0.5.0_1 [dependency]
```

## Build from Source

Build and install a VUP package locally:

```bash
vuru install odin --build
```

Vuru clones the VUP templates and build infrastructure into
`~/.local/share/vup` when needed. Run `vuru clone` to update an existing local
checkout.

### Local build dependency policy

Build mode applies recursively to the entire VUP dependency chain. Dependencies
available only through VUP are also built locally from their templates, while
dependencies available from official Void repositories are installed as
official binaries. VUP binary repositories cannot silently replace those local
VUP builds.

The transaction summary labels the requested package as `[explicit]` and its
dependencies as `[dependency]`. If a dependency fails to build, Vuru aborts the
target and prints the dependency chain leading to the failure.

A template may compile source code or package an upstream-provided binary. Local
mode follows the template and verifies its declared checksums, so users who want
to audit the full supply chain should review the target and dependency templates.
Use `--dry-run` to inspect the planned transaction without cloning, downloading,
building, or installing packages.

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

**vuru** (`vuru/src/` + `vup/scripts`) is licensed under the MIT License. See [LICENSE](LICENSE).

The **xbps-src build infrastructure** (`vup/common/`, `vup/etc/`) is BSD 2-Clause licensed, derived from [void-packages](https://github.com/void-linux/void-packages). See [vup/common/LICENSE](vup/common/LICENSE).

Package templates in `vup/srcpkgs/` carry their own license declarations via the `license=` field.
