# VUP – Void User Packages

**The easiest way to discover and install community packages on Void Linux.**

VUP extends your Void Linux experience by providing a community-driven repository of extra packages, fully compatible with your existing system. It’s strictly designed to "do no harm" no overriding web of dependencies, no complex infrastructure, just pure XBPS compatibility.



## Why VUP?

*   **⚡ Native Speed**: Uses your existing `xbps-install`. No slow wrappers.
*   **📦 Community Power**: Anyone can submit a package template.
*   **🛡️ Infrastructure Free**: Powered entirely by GitHub. No servers to go down.
*   **🔍 Easy Discovery**: The `vuru` tool makes finding packages instant.

> **Note**: VUP is an experimental, community project. It is not affiliated with the official Void Linux team.

## Why Vuru?

You might wonder why we use a separate tool (`vuru`) instead of just adding a repository to `xbps-install`.

*   **Safety**: We want to avoid polluting your core system commands with packages of unknown quality.
*   **Auditability**: `vuru` automatically shows you the package template (and diffs) before installation, ensuring you know exactly what you're running.
*   **Clarity**: `vuru` makes it explicit when you are venturing into community territory.
*   **Stability**: Official Void repositories remain untouched and pristine. `vuru` manages the "wild west" separately.

## Getting Started

### 1. Install VURU

VURU is the magic wand that connects your system to the VUP universe.

```bash
# Install vuru client from the core repository
sudo xbps-install -R https://github.com/VUP-Linux/vup/releases/download/core-current -S vuru
```

### 2. Use It

Once installed, use `vuru` to manage community packages. It feels just like home.

*   **Install a package**:
    ```bash
    vuru vscode
    ```
    *VURU automatically finds which category `vscode` lives in and installs it.*

*   **Search for packages**:
    ```bash
    vuru search spotify
    ```

*   **Update VUP packages**:
    ```bash
    vuru -u
    ```

*   **Remove a package**:
    ```bash
    vuru remove vscode
    ```

*   **list all available commands**:
    ```bash
    vuru -h
    ```
> [!WARNING]
> **Community Maintained Content**
> Packages in VUP are submitted by users. While we verify they compile, we **do not** audit them for safety or security. Use them at your own risk, just like the AUR.

## Contributing

Want to see a package here? **Add it!**

VUP is built on the principle that adding a package should be as simple as a Pull Request.

👉 **[Read our Contributing Guide](CONTRIBUTING.md)** to learn how to add templates.

## Licensing

MIT License. Hack away.
