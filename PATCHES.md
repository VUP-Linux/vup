# VUP Patches to void-packages

This document tracks modifications made to the upstream void-packages (xbps-src) codebase.

## common.sh - Category-aware template resolution

**File:** `vup/common/xbps-src/shutils/common.sh`

VUP uses a categorized `srcpkgs/` structure:
```
srcpkgs/<category>/<pkgname>/template
```

Instead of the flat upstream structure:
```
srcpkgs/<pkgname>/template
```

### Changes in `setup_pkg()`:

1. **Early Template Resolution**: Moved template path resolution logic to run *before* sourcing environment setup scripts. This ensures `git.sh` has access to the correct path.

2. **Category-aware path lookup**: Added logic to search `srcpkgs/*/<pkg>/template` if flat path is missing.

3. **Variables Export**:
   - `_srcpkg_dir`: Full path to the package directory.
   - `XBPS_PKG_CATEGORY`: The category name (if found).

4. **Updated Variables**: `FILESDIR` and `PATCHESDIR` now use `_srcpkg_dir` instead of hardcoded paths.

## git.sh - Use resolved package directory

**File:** `vup/common/environment/setup/git.sh`

- Updated `SOURCE_DATE_EPOCH` calculation to use `_srcpkg_dir` (if set) to correctly find template files in categorized structure.

## xbps-src - Category-aware triggers

**File:** `vup/xbps-src`

- Updated `XBPS_TRIGGERSDIR` definition to check `srcpkgs/core/xbps-triggers/files` before falling back to flat path, enabling triggers to be found in the categorized structure.
