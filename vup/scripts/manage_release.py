#!/usr/bin/env python3
import os
import sys
import subprocess
import glob
import re
import json
from functools import cmp_to_key

# Configuration
REPO = os.environ.get("GITHUB_REPOSITORY")
CATEGORY = os.environ.get("CATEGORY")
ARCH = os.environ.get("ARCH", "x86_64")
TAG_NAME = f"{CATEGORY}-{ARCH}-current"
DIST_DIR = "dist"

def run_command(cmd, capture_output=False):
    try:
        if capture_output:
            return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode().strip()
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
        if res: return res
    
    # Fallback/Remote logic
    # Match <name>-<version>_<revision>.<arch>.xbps
    # Find last hyphen before a digit
    match = re.search(r'^(.*)-([0-9][^-]*)\.[^.]*\.xbps$', os.path.basename(filename))
    if match:
        return match.group(1)
    return None

def get_pkg_ver(filename):
    # Try xbps-uhelper first
    if os.path.exists(filename):
        res = run_command(["xbps-uhelper", "binpkgver", filename], capture_output=True)
        if res: return res
    
    # Fallback regex extraction from filename
    # <name>-<version>_<revision>.<arch>.xbps
    base = os.path.basename(filename)
    match = re.search(r'-([0-9][^-]*_[0-9]+)\.[^.]*\.xbps$', base)
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
        parts = re.split(r'[._-]', v)
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
        if n1 > n2: return 1
        if n1 < n2: return -1
    except Exception:
        pass

    return 1 if v1 > v2 else -1

def download_release():
    print(f"Downloading assets from {TAG_NAME}...")
    os.makedirs(DIST_DIR, exist_ok=True)
    
    # Check if release exists
    if not run_command(["gh", "release", "view", TAG_NAME, "--repo", REPO], capture_output=True):
        print(f"Release {TAG_NAME} not found. Starting fresh.")
        return

    run_command(["gh", "release", "download", TAG_NAME, "--repo", REPO, "--dir", DIST_DIR, "--pattern", "*"])

def xbps_ver_cmp(f1, f2):
    v1 = get_pkg_ver(f1)
    v2 = get_pkg_ver(f2)
    
    if not v1 or not v2:
        print(f"Warning: Could not determine version for {f1} or {f2}")
        return 0
        
    # Python Fallback for same version different revision (most common cleanup case)
    # This avoids xbps-uhelper issues with revision comparison via cmpver if implementation varies
    # or if xbps-uhelper is missing.
    val1, rev1 = parse_ver_rev(v1)
    val2, rev2 = parse_ver_rev(v2)
    
    if val1 == val2:
        return 1 if rev1 > rev2 else (-1 if rev1 < rev2 else 0)

    # Try xbps-uhelper cmpver for different versions
    try:
        # Note: xbps-uhelper cmpver returns exit code, not stdout
        # 0: equal
        # 1: v1 > v2
        # 255 (-1): v1 < v2
        ret = subprocess.call(["xbps-uhelper", "cmpver", v1, v2], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if ret == 1: return 1
        if ret == 255: return -1
        # If 0, fall through to python cmp which handles it anyway
    except Exception:
        pass
        
    return python_ver_cmp(v1, v2)

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

def update_repository():
    """Signs packages (if key present), indexes them, and signs the repo."""
    print("Updating repository index...")
    
    # We expect to run from the parent of DIST_DIR, but xbps-rindex works best
    # when run inside the directory or we must be careful with paths.
    # To mimic previous behavior, we'll chdir into DIST_DIR.
    cwd = os.getcwd()
    try:
        if os.path.isdir(DIST_DIR):
            os.chdir(DIST_DIR)
        else:
            print(f"Directory {DIST_DIR} does not exist.")
            return

        privkey = os.environ.get("XBPS_PRIVATE_KEY")
        privkey_file = None
        
        # 1. Setup Private Key
        if privkey:
            # Write key to a file outside dist to avoid indexing it
            privkey_file = os.path.abspath("../privkey.pem")
            with open(privkey_file, "w") as f:
                f.write(privkey)
            print("Private key loaded.")

        # 2. Sign Individual Packages
        if privkey_file:
            print("Signing packages...")
            for pkg in glob.glob("*.xbps"):
                if not os.path.exists(pkg + ".sig"):
                    run_command(["xbps-rindex", "--sign-pkg", "--privkey", privkey_file, pkg])

        # 3. Generate Index
        print("Generating index...")
        pkgs = glob.glob("*.xbps")
        if pkgs:
            print(f"Found {len(pkgs)} packages to index: {pkgs}")
            # -a adds to index, -f forces indexing of foreign arch packages
            result = run_command(["xbps-rindex", "-f", "-a"] + pkgs)
            if result is None:
                print("ERROR: xbps-rindex failed to generate index!")
            else:
                # Verify repodata was created
                repodata_files = glob.glob("*-repodata*")
                print(f"Repodata files after indexing: {repodata_files}")
                if not repodata_files:
                    print("WARNING: No repodata files were generated!")
        else:
            print("WARNING: No .xbps packages found to index!")
        
        # 4. Sign Repository
        if privkey_file:
            print("Signing repository index...")
            run_command(["xbps-rindex", "--sign", "--privkey", privkey_file, "--signedby", "VUP Builder", "."])

    finally:
        # Cleanup
        if privkey_file and os.path.exists(privkey_file):
            os.remove(privkey_file)
            print("Private key cleaned up.")
        
        os.chdir(cwd)

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
    elif cmd == "update_repo":
        update_repository()
