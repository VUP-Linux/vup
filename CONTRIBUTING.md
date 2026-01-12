# Contributing to VUP

VUP is a community-driven repository. We welcome new packages and improvements!

## Repository Layout

* **[`vup/`](vup/)**: Source repository containing package templates and policy.
  * `srcpkgs/<category>/<pkgname>/template`
* **[`vuru/`](vuru/)**: The utility written in C for managing VUP packages.

## How to Add a Package

Platform packages are organized by **Category**. 

1.  **Fork** this repository.

2.  **Choose a Category**:
    *   Currently supported categories: `core`, `utilities`, `editors`, `chat`.
    *   *Note: If your package doesn't fit these, open an issue first.*
3.  **Create your Template**:
    *   Create directory: `vup/srcpkgs/<category>/<pkgname>/`
    *   Add a standard Void `template` file.
    *   *Note: Binary packages are NOT committed to the repo.*
4.  **Submit a Pull Request**:
    *   Our CI will automatically build your package if it detects changes in `vup/srcpkgs`.
    *   The build runs `xbps-src -Q pkg <pkgname>` to verify quality and linting.
    *   Once merged, it will be published to the `<category>-current` release suitable for `vuru`.

## Policy

VUP has **no content guidelines** regarding what packages can be submitted, provided they build correctly.
*   **Free for all**: If it builds, it is accepted.
*   **User Responsibility**: We do not audit code, check for licenses, or guarantee safety.

## Liability Disclaimer

> [!CAUTION]
> **Use at your own risk.**

VUP is similar to the AUR (Arch User Repository). Packages are submitted by community members.
*   **We only verify that the manifest builds.** We do not verify if the software is safe, non-malicious, or up-to-date.
*   By using VUP, you assume full responsibility for your system's stability and security.
*   Always check the template source if you are unsure.

### Template Guidelines

*   Follow standard [Void Linux packaging conventions](https://github.com/void-linux/void-packages/blob/master/Manual.md).
*   Ensure `license`, `homepage`, and `maintainer` are accurate.
*   **Electron/Prebuilt Binaries**: When packaging prebuilt binaries (especially Electron apps), you MUST set `noshlibprovides=yes`. This prevents the package from "providing" its internal bundled libraries (like `libffmpeg.so`) to the system, which would break dependency resolution for other packages.

## Architecture Overview

VUP uses an "All-GitHub" architecture to remain infrastructure-free:

### 1. Source & Build
*   GitHub Actions builds packages on `push` to `main`.
*   Only the modified category is rebuilt.

### 2. Binary Distribution
*   Each category corresponds to a **GitHub Release** tag (e.g., `editors-current`).
*   Binaries (`.xbps`) and repository data (`repodata`) are uploaded as assets.
*   These releases acts as standard XBPS remote repositories.

### 3. Global Index
*   A `public/index.json` is generated and hosted via GitHub Pages.
*   This index maps `pkgname` -> `category` + `version`.
*   The `vuru` client consumes this index to locate packages.

## Release Workflows

### VUP (Packages)
Packages are released continuously. 
To update a package:
1.  Bump version/revision in the template.
2.  Push to `main`.
3.  CI handles the rest.

### VURU (Client)
To release a new version of the `vuru` CLI:
1.  Bump version in `vuru/Cargo.toml`.
2.  Create and push a git tag (e.g., `v0.4.0`).
3.  CI builds the binary, creates a release, AND automatically updates the `vuru` package template in VUP.
