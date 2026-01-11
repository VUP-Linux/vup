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
            return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode().strip()
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
    # If file doesn't exist (remote listing), fallback to regex
    # Also skip xbps-uhelper for .xbps files as it expects pkgver string
    if os.path.exists(filename) and not filename.endswith(".xbps"):
        res = run_command(["xbps-uhelper", "getpkgname", filename], capture_output=True)
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

from functools import cmp_to_key

def xbps_ver_cmp(f1, f2):
    v1 = run_command(["xbps-uhelper", "binpkgver", f1], capture_output=True)
    v2 = run_command(["xbps-uhelper", "binpkgver", f2], capture_output=True)
    
    if not v1 or not v2:
        return 0
        
    # xbps-uhelper cmpver v1 v2
    # Returns 0 (eq), 1 (v1>v2), 255 (v1<v2)
    # We want standard -1, 0, 1
    try:
        # Note: xbps-uhelper cmpver returns exit code, not stdout
        # 0: equal
        # 1: v1 > v2
        # 255 (-1): v1 < v2
        ret = subprocess.call(["xbps-uhelper", "cmpver", v1, v2], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if ret == 1: return 1
        if ret == 255: return -1
        return 0
    except Exception:
        return 0

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
                print(f"Warning: Could not determine package name for {os.path.basename(f)}")

    for name, fpaths in pkgs.items():
        if len(fpaths) > 1:
            fpaths.sort(key=cmp_to_key(xbps_ver_cmp), reverse=True)
            print(f"Versions for {name}: {[os.path.basename(fv) for fv in fpaths]}")
            
            for old in fpaths[1:]:
                print(f"Removing old version: {os.path.basename(old)}")
                os.remove(old)
                if os.path.exists(old + ".sig"): os.remove(old + ".sig")
                if os.path.exists(old + ".sig2"): os.remove(old + ".sig2")

    # 2. Clean orphaned signatures and other artifacts
    print("Cleaning orphaned files...")
    all_files = glob.glob(os.path.join(DIST_DIR, "*"))
    for f in all_files:
        if os.path.isdir(f): continue
        if f.endswith(".xbps"): continue
        
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
    """Delete remote assets that are NOT present in local DIST_DIR."""
    print("Synchronizing remote assets (Deleting obsolete)...")
    
    try:
        json_str = run_command(["gh", "release", "view", TAG_NAME, "--repo", REPO, "--json", "assets"], capture_output=True)
        data = json.loads(json_str)
        remote_assets = {a['name']: a for a in data.get('assets', [])}
    except Exception:
        print("Could not fetch remote assets (maybe release doesn't exist yet).")
        return

    local_assets = set(os.path.basename(f) for f in glob.glob(os.path.join(DIST_DIR, "*")))

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
