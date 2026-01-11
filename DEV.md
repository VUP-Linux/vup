# VUP Architecture (All-GitHub)

**Concept**: GitHub hosts source (templates), execution (CI), and artifacts (releases).  
**Goal**: Zero infrastructure cost, unlimited scale, standard XBPS compatibility.

## 1. Installing VURU (Client)
To install the VURU client from the rolling release:

```bash
# Install VURU
sudo xbps-install -R https://github.com/void-linux/vup/releases/download/vuru-current -S vuru
```

## 2. Source Layout
- **Repo**: `VUP-Linux/vup` (or similar).
- **Templates**: `srcpkgs/<category>/<pkgname>/template`.
- **Binaries**: NEVER committed.

## 3. Release Strategy (The "Sub-Repo")
- **Mechanism**: GitHub Releases act as individual XBPS repositories.
- **Tag Naming**: `<category>-current` (e.g., `utilities-current`, `editors-current`).
- **Assets**: `repodata`, `*.xbps`.
- **Retention**: Overwrite `*-current` on every build. Service stateless.

## 4. URLs
- **XBPS Repository URL**:
  `https://github.com/<OWNER>/<REPO>/releases/download/<CATEGORY>-current/`
- **Example**:
  `xbps-install -R https://github.com/VUP-Linux/vup/releases/download/editors-current/ vscode`

## 5. Global Index
- **File**: `index.json` (GitHub Pages or Release Asset).
- **Structure**:
  ```json
  {
    "vscode": { "category": "editors", "version": "1.90.0_1" },
    "antigravity": { "category": "utilities", "version": "1.13.3_1" }
  }
  ```

## 6. Client (VURU)
1. **Fetch** `index.json`.
2. **Lookup** `pkg` → `category`.
3. **Construct** Release URL.
4. **Exec** `xbps-install -R <URL> <pkg>`.

## 7. Release Workflow

### Releasing Packages (VUP)
Packages are built automatically when their template is modified.
1. **Push Changes**: Modify `srcpkgs/<category>/<pkgname>/template`.
2. **Commit & Push**: `git push origin main`.
3. **Result**: CI builds only the modified category and updates the `<category>-current` release.
4. **Manual**: Go to Actions -> Build and Release -> Run workflow -> Select Branch & Category.

### Releasing VURU (Client)
The VURU client has its own dedicated workflow.
1. **Tag**: Create a tag starting with `v` (e.g., `v0.1.0`).
   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```
2. **Result**: CI builds the `vuru` binary and updates the `vuru-current` release.
