#!/usr/bin/env python3
"""
Manage VUP releases - handles both GitHub releases (repodata) and Cloudflare R2 (packages).
"""

import glob
import json
import os
import re
import subprocess
import sys
from functools import cmp_to_key
from typing import Optional, Union

# Configuration from environment
REPO: str = os.environ.get("GITHUB_REPOSITORY", "")
CATEGORY: str = os.environ.get("CATEGORY", "")
ARCH: str = os.environ.get("ARCH", "x86_64")
TAG_NAME: str = f"{CATEGORY}-{ARCH}-current"
DIST_DIR: str = "dist"


def run_command(
    cmd: list[str], capture_output: bool = False
) -> Optional[Union[str, bool]]:
    """Run a command, returning output string if capture_output, True on success, None on failure."""
    try:
        if capture_output:
            return (
                subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode().strip()
            )
        subprocess.check_call(cmd)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        if not capture_output:
            print(f"Command failed: {e}")
        return None


def get_pkg_name(filename):
    # Also skip xbps-uhelper for .xbps files as it expects pkgver string
    if os.path.exists(filename) and not filename.endswith(".xbps"):
        res = run_command(["xbps-uhelper", "getpkgname", filename], capture_output=True)
        if res:
            return res

    # Fallback/Remote logic
    # Match <name>-<version>_<revision>.<arch>.xbps
    # Find last hyphen before a digit
    match = re.search(r"^(.*)-([0-9][^-]*)\.[^.]*\.xbps$", os.path.basename(filename))
    if match:
        return match.group(1)
    return None


def get_pkg_ver(filename):
    # Try xbps-uhelper first
    if os.path.exists(filename):
        res = run_command(["xbps-uhelper", "binpkgver", filename], capture_output=True)
        if res:
            return res

    # Fallback regex extraction from filename
    # <name>-<version>_<revision>.<arch>.xbps
    base = os.path.basename(filename)
    match = re.search(r"-([0-9][^-]*_[0-9]+)\.[^.]*\.xbps$", base)
    if match:
        return match.group(1)

    return None


def parse_ver_rev(version_str):
    """Splits version_revision string into (version, revision_int)."""
    if "_" in version_str:
        ver, rev = version_str.rsplit("_", 1)
        try:
            return ver, int(rev)
        except ValueError:
            return ver, 0
    return version_str, 0


def python_ver_cmp(v1, v2):
    """Fallback comparison logic."""
    ver1, rev1 = parse_ver_rev(v1)
    ver2, rev2 = parse_ver_rev(v2)

    if ver1 == ver2:
        return 1 if rev1 > rev2 else (-1 if rev1 < rev2 else 0)

    # Simple version comparison - split by common separators and compare parts
    def normalize(v):
        # Split version string into comparable parts
        parts = re.split(r"[._-]", v)
        result = []
        for p in parts:
            # Try to convert to int for numeric comparison
            try:
                result.append((0, int(p)))
            except ValueError:
                result.append((1, p))  # String parts sort after numbers
        return result

    try:
        n1, n2 = normalize(ver1), normalize(ver2)
        if n1 > n2:
            return 1
        if n1 < n2:
            return -1
    except Exception:
        pass

    return 1 if v1 > v2 else -1


def download_release():
    print(f"Downloading assets from {TAG_NAME}...")
    os.makedirs(DIST_DIR, exist_ok=True)

    if not REPO:
        print("ERROR: GITHUB_REPOSITORY not set")
        return

    # Check if release exists
    if not run_command(
        ["gh", "release", "view", TAG_NAME, "--repo", REPO], capture_output=True
    ):
        print(f"Release {TAG_NAME} not found. Starting fresh.")
        return

    run_command(
        [
            "gh",
            "release",
            "download",
            TAG_NAME,
            "--repo",
            REPO,
            "--dir",
            DIST_DIR,
            "--pattern",
            "*",
        ]
    )


def xbps_ver_cmp(f1, f2):
    v1 = get_pkg_ver(f1)
    v2 = get_pkg_ver(f2)

    if not v1 or not v2:
        print(f"Warning: Could not determine version for {f1} or {f2}")
        return 0

    # Python Fallback for same version different revision (most common cleanup case)
    val1, rev1 = parse_ver_rev(v1)
    val2, rev2 = parse_ver_rev(v2)

    if val1 == val2:
        return 1 if rev1 > rev2 else (-1 if rev1 < rev2 else 0)

    # Try xbps-uhelper cmpver for different versions
    try:
        ret = subprocess.call(
            ["xbps-uhelper", "cmpver", v1, v2],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if ret == 1:
            return 1
        if ret == 255:
            return -1
    except Exception:
        pass

    return python_ver_cmp(v1, v2)


def clean_stale_sigs():
    """Remove signatures for packages that have been rebuilt (sig is older than pkg)."""
    print("Cleaning stale signatures...")
    for pkg in glob.glob(os.path.join(DIST_DIR, "*.xbps")):
        for ext in [".sig", ".sig2"]:
            sig = pkg + ext
            if os.path.exists(sig):
                # If signature is older than the package, it's stale
                pkg_mtime = os.path.getmtime(pkg)
                sig_mtime = os.path.getmtime(sig)
                if sig_mtime < pkg_mtime:
                    print(f"Removing stale signature: {os.path.basename(sig)}")
                    os.remove(sig)


def prune_local():
    """Keep only the latest version of each package in DIST_DIR."""
    print("Pruning local old versions...")
    files = glob.glob(os.path.join(DIST_DIR, "*.xbps"))

    # 1. Prune duplicate/old versions
    pkgs = {}
    if files:
        for f in files:
            name = get_pkg_name(f)
            if name:
                pkgs.setdefault(name, []).append(f)
            else:
                print(
                    f"Warning: Could not determine package name for {os.path.basename(f)}"
                )

    for name, fpaths in pkgs.items():
        if len(fpaths) > 1:
            fpaths.sort(key=cmp_to_key(xbps_ver_cmp), reverse=True)
            print(f"Versions for {name}: {[os.path.basename(fv) for fv in fpaths]}")

            for old in fpaths[1:]:
                print(f"Removing old version: {os.path.basename(old)}")
                os.remove(old)
                if os.path.exists(old + ".sig"):
                    os.remove(old + ".sig")
                if os.path.exists(old + ".sig2"):
                    os.remove(old + ".sig2")

    # 2. Clean orphaned signatures and other artifacts
    print("Cleaning orphaned files...")
    all_files = glob.glob(os.path.join(DIST_DIR, "*"))
    for f in all_files:
        if os.path.isdir(f):
            continue
        if f.endswith(".xbps"):
            continue

        # Skip repodata files
        basename = os.path.basename(f)
        if basename == "repodata" or basename.startswith("repodata."):
            continue

        # Check if it is a signature for a missing package
        parent = None
        if f.endswith(".sig"):
            parent = f[:-4]
        elif f.endswith(".sig2"):
            parent = f[:-5]

        if parent:
            if not os.path.exists(parent):
                print(f"Removing orphaned signature: {basename}")
                os.remove(f)


def clean_remote_assets():
    """Delete remote GitHub assets that are NOT present in local DIST_DIR."""
    print("Synchronizing remote GitHub assets (Deleting obsolete)...")

    if not REPO:
        print("ERROR: GITHUB_REPOSITORY not set")
        return

    try:
        json_str = run_command(
            ["gh", "release", "view", TAG_NAME, "--repo", REPO, "--json", "assets"],
            capture_output=True,
        )
        if not json_str or not isinstance(json_str, str):
            raise ValueError("No response from gh release view")
        data = json.loads(json_str)
        remote_assets = {a["name"]: a for a in data.get("assets", [])}
    except Exception:
        print("Could not fetch remote assets (maybe release doesn't exist yet).")
        return

    local_assets = set(
        os.path.basename(f) for f in glob.glob(os.path.join(DIST_DIR, "*"))
    )

    print(f"Local assets in {DIST_DIR}: {sorted(local_assets)}")
    print(f"Remote assets: {sorted(remote_assets.keys())}")

    to_delete = []
    for r_name in remote_assets:
        if r_name not in local_assets:
            to_delete.append(r_name)

    if not to_delete:
        print("Remote is clean.")
        return

    for asset in to_delete:
        print(f"Deleting remote asset: {asset}")
        run_command(
            ["gh", "release", "delete-asset", TAG_NAME, asset, "--repo", REPO, "--yes"]
        )


# ============================================================================
# Main
# ============================================================================

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: manage_release.py [download|prune|clean_remote]")
        print()
        print("Commands:")
        print("  download     - Download existing release assets from GitHub")
        print("  prune        - Remove old package versions locally")
        print("  clean_remote - Delete obsolete assets from GitHub release")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "download":
        download_release()
    elif cmd == "prune":
        prune_local()
        clean_stale_sigs()
    elif cmd == "clean_remote":
        clean_remote_assets()
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)
