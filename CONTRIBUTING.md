# Contributing to VUP

VUP is a community-driven repository. Packages and improvements welcome.

## Repository Structure

```
vup/srcpkgs/<category>/<pkgname>/template
vuru/                                     # package manager (Odin)
```

## Adding a Package

1. Fork the repo.

2. Pick a category: `core`, `utilities`, `editors`, `messenger`, `programming`.
   If your package doesn't fit, open an issue first.

3. Create your template at `vup/srcpkgs/<category>/<pkgname>/template`.
   Follow standard [Void packaging conventions](https://github.com/void-linux/void-packages/blob/master/Manual.md).

4. Open a PR. CI will automatically validate your template for required fields. If it passes, a maintainer will add the `ok-to-build` label to trigger a build. A bot will comment with results.

That's it. Once merged, the package shows up in the VUP index.

## Template Notes

Follow the Void manual, but a few VUP-specific things:

**Electron/prebuilt apps**: Set `noshlibprovides=yes`. This prevents the package from advertising its bundled libraries (like `libffmpeg.so`) to the system, which breaks dep resolution for other packages.

**Maintainer field**: Put your name/email. You're responsible for updates.

**License**: Be accurate. We don't audit this, but users should know what they're installing.

## Policy

VUP has no content restrictions. If it builds, it's accepted.

This is intentional. Like the AUR, we're a build system, not a software review board. We verify the template syntax and that the build succeeds. We don't verify if the software is safe, legal, maintained or sane.

## Liability

> **Use at your own risk.**

Packages are submitted by random people on the internet. We only check that the manifest builds. We don't:
- Audit source code
- Check for malware
- Verify licenses
- Guarantee anything works

By using VUP, you accept responsibility for what you install. If you're paranoid (and you should be), read the template before installing.

## Architecture

VUP runs entirely on GitHub infrastructure:

**Build**: GitHub Actions builds packages on push to main. Only modified categories rebuild.

**Distribution**: Each category has a GitHub Release (e.g. `{category-{architecture}-current`). The `*.xbps`, `*.xbps.sig2` files and `{architecture}-repodata` are release assets. These releases act as standard XBPS repositories.

**Index**: A `public/index.json` on GitHub Pages maps package names to categories, architectures and versions. vuru fetches this to find packages.


## Updating Packages

Bump the version or revision in the template and push. CI handles the rest.

## Local Validation

Run this before opening a PR to catch template issues early:

```bash
make check
```

This validates all templates for required fields (`pkgname`, `version`, `revision`, `license`, `homepage`, `distfiles`, `short_desc`, `maintainer`).

To build a package locally using Docker (same environment as CI):

```bash
docker run --rm --privileged -v $PWD:/vup \
  ghcr.io/vup-linux/vup-builder:latest sh -c '
    cd /vup/vup/srcpkgs/<category>/<pkgname> && xbps-src pkg <pkgname>'
```

## PR Title Convention

- **New package:** `feat: add <pkgname>` or `feat: add <pkgname> <version>`
- **Update:** `<pkgname>: update to <version>`
- **Fixes/chores/docs:** `fix:`, `chore:`, `docs:`, `ci:`

A CI check will remind you if the title doesn't match.

## xbps-src Patches

If you're modifying `xbps-src` itself or the build infrastructure (`vup/common/`, `vup/xbps-src`), see [PATCHES.md](PATCHES.md) for a record of changes made to the upstream void-packages codebase.

## Contributing to vuru

**vuru** is the package manager for VUP, written in Odin. It lives in `vuru/`.

### Building

```bash
cd vuru
make          # release build
make debug    # debug build
```

### Installing

```bash
sudo make install
```

### Release Flow

1. Push a version tag (`vX.Y.Z`) — this triggers the `vuru-release.yml` workflow
2. CI creates a source tarball and attaches it to a GitHub Release
3. CI opens a PR to update `vup/srcpkgs/core/vuru/template` with the new version and checksum
4. Merge that PR and the build workflow publishes the updated package