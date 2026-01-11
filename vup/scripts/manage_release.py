#!/usr/bin/env python3
import os
import sys
import subprocess
import glob
import re
import shutil
import json

# Configuration
REPO = os.environ.get("GITHUB_REPOSITORY")
CATEGORY = os.environ.get("CATEGORY")
TAG_NAME = f"{CATEGORY}-current"
DIST_DIR = "dist"

def run_command(cmd, capture_output=False):
    try:
        if capture_output:
            return subprocess.check_output(cmd).decode().strip()
        subprocess.check_call(cmd)
        return True
    except subprocess.CalledProcessError as e:
        if not capture_output:
            print(f"Command failed: {e}")
        return None

def get_pkg_name(filename):
    # Use xbps-uhelper if available for accurate parsing
    # xbps-uhelper getpkgname <binpkg>
    # If file doesn't exist (remote listing), fallback to regex
    if os.path.exists(filename):
        res = run_command(["xbps-uhelper", "getpkgname", os.path.basename(filename)], capture_output=True)
        if res: return res
    
    # Fallback/Remote logic
    # Match <name>-<version>_<revision>.<arch>.xbps
    # Find last hyphen before a digit
    match = re.search(r'^(.*)-([0-9][^-]*)\.[^.]*\.xbps$', os.path.basename(filename))
    if match:
        return match.group(1)
    return None

def get_pkg_ver(filename):
    if os.path.exists(filename):
        res = run_command(["xbps-uhelper", "binpkgver", filename], capture_output=True)
        if res: return res
    return None

def download_release():
    print(f"Downloading assets from {TAG_NAME}...")
    os.makedirs(DIST_DIR, exist_ok=True)
    
    # Check if release exists
    if not run_command(["gh", "release", "view", TAG_NAME, "--repo", REPO], capture_output=True):
        print(f"Release {TAG_NAME} not found. Starting fresh.")
        return

    run_command(["gh", "release", "download", TAG_NAME, "--repo", REPO, "--dir", DIST_DIR, "--pattern", "*"])

def prune_local():
    """Keep only the latest version of each package in DIST_DIR."""
    print("Pruning local old versions...")
    files = glob.glob(os.path.join(DIST_DIR, "*.xbps"))
    if not files: return

    pkgs = {}
    for f in files:
        name = get_pkg_name(f)
        if name:
            pkgs.setdefault(name, []).append(f)

    for name, fpaths in pkgs.items():
        if len(fpaths) > 1:
            # Sort using xbps-uhelper cmpver logic conceptually
            # We assume xbps-uhelper is available in the container
            fpaths.sort(key=lambda x: run_command(["xbps-uhelper", "binpkgver", x], capture_output=True), reverse=True)
            
            # Keep index 0 (newest), delete others
            for old in fpaths[1:]:
                print(f"Removing old version: {os.path.basename(old)}")
                os.remove(old)
                if os.path.exists(old + ".sig"): os.remove(old + ".sig")

def clean_remote_assets():
    """Delete remote assets that are NOT present in local DIST_DIR."""
    print("Synchronizing remote assets (Deleting obsolete)...")
    
    # Get remote assets
    try:
        json_str = run_command(["gh", "release", "view", TAG_NAME, "--repo", REPO, "--json", "assets"], capture_output=True)
        data = json.loads(json_str)
        remote_assets = {a['name']: a for a in data.get('assets', [])}
    except Exception:
        print("Could not fetch remote assets (maybe release doesn't exist yet).")
        return

    # Get local assets (filenames only)
    local_assets = set(os.path.basename(f) for f in glob.glob(os.path.join(DIST_DIR, "*")))

    # Repodata is always regenerated/overwritten, but we should treat it same
    # Identify orphans
    to_delete = []
    for r_name in remote_assets:
        if r_name not in local_assets:
            to_delete.append(r_name)

    if not to_delete:
        print("Remote is clean.")
        return

    for asset in to_delete:
        print(f"Deleting remote asset: {asset}")
        run_command(["gh", "release", "delete-asset", TAG_NAME, asset, "--repo", REPO, "--yes"])

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: manage_release.py [download|prune|clean_remote]")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "download":
        download_release()
    elif cmd == "prune":
        prune_local()
    elif cmd == "clean_remote":
        clean_remote_assets()
