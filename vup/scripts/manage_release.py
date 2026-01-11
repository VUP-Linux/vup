#!/usr/bin/env python3
import os
import sys
import subprocess
import glob
import re
import shutil

# Configuration
REPO = os.environ.get("GITHUB_REPOSITORY")
CATEGORY = os.environ.get("CATEGORY")
TAG_NAME = f"{CATEGORY}-current"
DIST_DIR = "dist"

def run_command(cmd, shell=False):
    print(f"Running: {cmd}")
    try:
        subprocess.check_call(cmd, shell=shell)
    except subprocess.CalledProcessError as e:
        print(f"Command failed: {e}")
        # Don't exit yet, might be non-fatal (e.g. release not found)
        return False
    return True

def download_current_release():
    """Downloads all assets from the current release to DIST_DIR."""
    print(f"Downloading assets from {TAG_NAME}...")
    os.makedirs(DIST_DIR, exist_ok=True)
    
    # Check if release exists
    if not run_command(["gh", "release", "view", TAG_NAME, "--repo", REPO]):
        print(f"Release {TAG_NAME} does not exist yet. Starting fresh.")
        return

    # Download everything
    # in a real container, 'gh' must be installed and authenticated
    cmd = ["gh", "release", "download", TAG_NAME, "--repo", REPO, "--dir", DIST_DIR, "--pattern", "*"]
    if not run_command(cmd):
        print("Failed to download assets (or none existed).")

def prune_old_versions():
    """
    Scans DIST_DIR for multiple versions of the same package and removes older ones.
    Relies on xbps naming convention: <pkgname>-<version>_<revision>.<arch>.xbps
    """
    print("Pruning old versions...")
    files = glob.glob(os.path.join(DIST_DIR, "*.xbps"))
    if not files:
        return

    # Map pkgname -> list of files
    # Regex to parse: name-version_revision.arch.xbps
    # This is a heuristic. reliable XBPS parsing requires xbps-uhelper or complex regex.
    # Pattern: match anything up to the last hyphen before a digit.
    
    # Simpler approach: Use `xbps-rindex -r` (remove obsolete) if available, 
    # but we are just managing files.
    
    # Let's use a robust heuristic: grouping by package name.
    pkgs = {}
    
    for fpath in files:
        fname = os.path.basename(fpath)
        # Regex: matches "pkgname" from "pkgname-1.2.3_1.x86_64.xbps"
        # It looks for the last hyphen followed by a digit
        match = re.search(r'^(.*)-([0-9].*)\.xbps$', fname)
        if match:
            pkgname = match.group(1)
            if pkgname not in pkgs:
                pkgs[pkgname] = []
            pkgs[pkgname].append(fpath)
    
    for pkgname, fpaths in pkgs.items():
        if len(fpaths) > 1:
            # Sort by generic version sort (not perfect but decent for strict filename sort)
            # For perfect sort, we need `xbps-uhelper cmpver`.
            # In the void container, we have xbps utils.
            
            # Using `xbps-uhelper getpkgname` and comparison is safer if possible.
            # But let's assume standard sorting for this script or call xbps-uhelper.
            
            # Sort descending (newest first)
            # We trust that the build process put the NEWEST file here recently.
            # Actually, `ls -t` or mtime might be unreliable if we just downloaded old ones.
            # We must use version comparison.
            
            fpaths.sort(key=lambda x: run_command_output(["xbps-uhelper", "getpkgver", x]), reverse=True)
            
            # Keep index 0, delete the rest
            keep = fpaths[0]
            remove = fpaths[1:]
            
            print(f"Keeping {os.path.basename(keep)}")
            for r in remove:
                print(f"Removing old version: {os.path.basename(r)}")
                os.remove(r)
                # Also try to remove sig file if exists
                if os.path.exists(r + ".sig"):
                    os.remove(r + ".sig")

def run_command_output(cmd):
    return subprocess.check_output(cmd).decode().strip()

def delete_remote_assets(assets_to_delete):
    """Deletes specific assets from the GitHub Release."""
    for asset in assets_to_delete:
        print(f"Deleting remote asset: {asset}")
        run_command(["gh", "release", "delete-asset", TAG_NAME, asset, "--repo", REPO, "--yes"])

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "download":
        download_current_release()
    elif len(sys.argv) > 1 and sys.argv[1] == "prune":
        prune_old_versions()
    else:
        print("Usage: manage_release.py [download|prune]")
