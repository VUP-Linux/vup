# VUP Architecture (All-GitHub)

**Concept**: GitHub hosts source (templates), execution (CI), and artifacts (releases).  
**Goal**: Zero infrastructure cost, unlimited scale, standard XBPS compatibility.

## 1. Source Layout
- **Repo**: `VUP-Linux/vup` (or similar).
- **Templates**: `srcpkgs/<category>/<pkgname>/template`.
- **Binaries**: NEVER committed.

## 2. Release Strategy (The "Sub-Repo")
- **Mechanism**: GitHub Releases act as individual XBPS repositories.
- **Tag Naming**: `<category>-current` (e.g., `utilities-current`, `editors-current`).
- **Assets**: `repodata`, `*.xbps`.
- **Retention**: Overwrite `*-current` on every build. Service stateless.

## 3. URLs
- **XBPS Repository URL**:
  `https://github.com/<OWNER>/<REPO>/releases/download/<CATEGORY>-current/`
- **Example**:
  `xbps-install -R https://github.com/VUP-Linux/vup/releases/download/editors-current/ vscode`

## 4. Global Index
- **File**: `index.json` (GitHub Pages or Release Asset).
- **Structure**:
  ```json
  {
    "vscode": { "category": "editors", "version": "1.90.0_1" },
    "antigravity": { "category": "utilities", "version": "1.13.3_1" }
  }
  ```

## 5. Client (VURU)
1. **Fetch** `index.json`.
2. **Lookup** `pkg` → `category`.
3. **Construct** Release URL.
4. **Exec** `xbps-install -R <URL> <pkg>`.
