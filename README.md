# VUP – Void User Protocols

VUP is an **experimental, community-driven packaging workflow for Void Linux** designed to improve third-party package availability and discovery **without changing Void’s core model**.

It is fully compatible with **XBPS**, requires **no new infrastructure**, and uses **GitHub only** for source, builds, and binary distribution.

> ⚠️ This project is **not official**, **not a replacement for `void-packages`**, and **not a new package manager**.

## Installing VURU (Client)

Install the rolling release of the VURU client:

```bash
sudo xbps-install -R https://github.com/VUP-Linux/vup/releases/download/core-current -S vuru
```

Once installed, VURU will handle locating and installing VUP packages automatically. It can even update itself using vuru

## What This Project Provides

### **VUP (Void User Packages)**

A community-maintained repository of Void package templates.

* Follows standard `void-packages` conventions
* Organised by category
* Built automatically via CI
* Outputs **binary XBPS repositories**

### **VURU**

A lightweight client that consumes VUP as a binary repository.

* Fetches a global package index
* Resolves package → category automatically
* Invokes `xbps-install` with the correct repository URL
* Does **not** replace XBPS

## Goals

* Make third-party packages **easy to discover and install**
* Remain stateless, transparent, and auditable

### Current Status

VUP is **actively working and usable**.

* CI workflows successfully build packages from templates
* Binary packages are uploaded to GitHub Releases as XBPS repositories
* VURU installs and resolves packages correctly using the global index
* No custom tooling is required beyond `xbps-install`

Development is currently focused on:

* Expanding the package set
* Hardening workflows
* Identifying and handling edge cases in real-world usage

Expect iteration and occasional breakage as coverage grows.


### Trust & Security Notice

VUP is a **user-maintained repository**.

While package templates and manifests may be reviewed or audited by maintainers, **there is no guarantee that any packaged software is safe, secure, or appropriate for your system**.

The **only guarantees provided** are that:

* The package template built successfully in CI
* The resulting binary can be installed via XBPS
* The repository layout follows standard Void conventions

Users are responsible for:

* Evaluating the software they install
* Reviewing templates and upstream sources
* Assessing risk, especially for newer or less common packages

If you require strict trust guarantees, security vetting, or long-term support, use the official `void-packages` repository instead.

## Repository Layout

### Projects

* **[`vup/`](vup/)**
  Source repository containing:

  * `srcpkgs/` package templates
  * Policy and structure

  Templates are organised as:

  ```
  srcpkgs/<category>/<pkgname>/template
  ```

  **Binary packages are never committed to the repository.**

* **[`vuru/`](vuru/)**
  The VURU client (written in Rust):

  * Searches available packages
  * Resolves repository URLs
  * Delegates installs to `xbps-install`

## Architecture Overview (All GitHub)

**Concept:**
GitHub hosts **source**, **execution**, and **artifacts**.

**Result:**
Zero infrastructure cost, unlimited scale, native XBPS compatibility.

### 1. Source

* GitHub repository: `VUP-Linux/vup`
* Package templates under `srcpkgs/<category>/<pkgname>/`

### 2. Binary Distribution (GitHub Releases)

Each category acts like its own XBPS repository using GitHub Releases.

* **Release Tags:**

  ```
  <category>-current
  ```

  Examples:

  * `editors-current`
  * `utilities-current`

* **Assets:**

  * `repodata`
  * `*.xbps`

* Releases are **overwritten on each build**
  (stateless, always current)

### 3. Repository URLs

XBPS-compatible repository URLs:

```
https://github.com/<OWNER>/<REPO>/releases/download/<CATEGORY>-current/
```

Example:

```bash
xbps-install -R https://github.com/VUP-Linux/vup/releases/download/editors-current/ vscode
```

---

## Global Package Index

A single `index.json` file maps packages to categories.

* Hosted via GitHub Pages or as a release asset
* Consumed by VURU

Example structure:

```json
{
  "vscode": { "category": "editors", "version": "1.90.0_1" },
  "antigravity": { "category": "utilities", "version": "1.13.3_1" }
}
```

---

## How VURU Works

1. Fetches `index.json`
2. Resolves the package’s category
3. Constructs the correct release URL
4. Executes:

   ```bash
   xbps-install -R <category-url> <package>
   ```

No wrapping, no patching, no daemon — just XBPS.

---

## Release Workflows

### Releasing Packages (VUP)

Packages are built automatically when their templates change.

1. Modify:

   ```
   srcpkgs/<category>/<pkgname>/template
   ```
2. Commit and push to `main`
3. CI builds **only the affected category**
4. Updates the corresponding `<category>-current` release

Manual runs are also available via GitHub Actions.

---

### Releasing the VURU Client

VURU has its own release workflow.

1. Create a version tag:

   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```
2. CI builds the binary
3. Updates the `vuru-current` release

---

## Documentation

* **[DEV.md](DEV.md)** – Architecture details, design rationale, and implementation notes

