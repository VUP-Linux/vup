# VUP - Void User Protocols

This repository contains the ecosystem for **VUP** (Void User Protocols/Packages), an experimental community packaging layer for Void Linux.

## Projects

*   **[vup/](vup/)**: The source repository for package templates, CI workflows, and policy.
    *   Contains `srcpkgs/` organized by categories (`editors`, `utilities`, `chat`).
    *   Builds binary packages to GitHub Releases.
*   **[vuru/](vuru/)**: The client utility (Rust).
    *   Manages searching and installing packages from VUP.
    *   Uses the global `index.json`.

## Documentation

*   [DEV.md](DEV.md): Architecture and Design documentation.

## Architecture

*   **Source**: GitHub Repo `VUP-Linux/vup`.
*   **Binaries**: GitHub Releases (`<category>-current`).
*   **Index**: Global JSON hosted on GitHub.
