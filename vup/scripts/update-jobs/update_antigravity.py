#!/usr/bin/env python3
"""
Auto-updater for antigravity package.
Uses apt tools to fetch the latest version info from the APT repository.
"""

import os
import re
import sys
import tempfile
import subprocess
import hashlib
import urllib.request
from pathlib import Path

TEMPLATE_PATH = Path(__file__).parent.parent.parent / "srcpkgs/editors/antigravity/template"

# APT repository configuration
REPO_URL = "https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev"
REPO_KEY_URL = "https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg"
DIST = "antigravity-debian"
PACKAGE_NAME = "antigravity"

# Map void arch to debian arch
ARCH_MAP = {
    "x86_64": "amd64",
    "aarch64": "arm64",
}


def version_tuple(v: str) -> tuple:
    """Convert version string to comparable tuple."""
    return tuple(map(int, v.split(".")))


def setup_apt_repo(temp_dir: str, arch: str) -> bool:
    """Set up the APT repository for querying."""
    deb_arch = ARCH_MAP[arch]
    keyring_path = f"{temp_dir}/antigravity.gpg"
    sources_path = f"{temp_dir}/sources.list"
    
    # Download and dearmor the key
    try:
        subprocess.run(
            f'curl -fsSL "{REPO_KEY_URL}" | gpg --batch --yes --dearmor -o "{keyring_path}"',
            shell=True, check=True, capture_output=True
        )
    except subprocess.CalledProcessError as e:
        print(f"  Failed to download repo key: {e}")
        return False
    
    # Create sources list
    with open(sources_path, "w") as f:
        f.write(f"deb [signed-by={keyring_path} arch={deb_arch}] {REPO_URL}/ {DIST} main\n")
    
    # Update apt cache for this repo
    try:
        subprocess.run(
            ["apt-get", "update", 
             "-o", f"Dir::Etc::sourcelist={sources_path}",
             "-o", "Dir::Etc::sourceparts=-",
             "-o", f"Dir::State={temp_dir}/state",
             "-o", f"Dir::Cache={temp_dir}/cache"],
            check=True, capture_output=True
        )
    except subprocess.CalledProcessError as e:
        print(f"  Failed to update apt cache: {e.stderr.decode()}")
        return False
    
    return True


def get_package_info_apt(temp_dir: str, arch: str) -> dict | None:
    """Get package info using apt-cache."""
    deb_arch = ARCH_MAP[arch]
    sources_path = f"{temp_dir}/sources.list"
    keyring_path = f"{temp_dir}/antigravity.gpg"
    
    apt_opts = [
        "-o", f"Dir::Etc::sourcelist={sources_path}",
        "-o", "Dir::Etc::sourceparts=-",
        "-o", f"Dir::State={temp_dir}/state",
        "-o", f"Dir::Cache={temp_dir}/cache",
    ]
    
    # Get version using apt-cache madison
    try:
        result = subprocess.run(
            ["apt-cache", *apt_opts, "madison", PACKAGE_NAME],
            capture_output=True, text=True, check=True
        )
        if not result.stdout.strip():
            return None
        
        # Parse: antigravity | 1.13.3-1766182170 | https://... antigravity-debian/main amd64 Packages
        line = result.stdout.strip().split("\n")[0]
        parts = [p.strip() for p in line.split("|")]
        version_full = parts[1]  # e.g., "1.13.3-1766182170"
        version = version_full.split("-")[0]
        build_id = version_full.split("-")[1] if "-" in version_full else ""
        
    except subprocess.CalledProcessError:
        return None
    
    # Get download URL using apt-get download --print-uris
    try:
        result = subprocess.run(
            ["apt-get", *apt_opts, "download", "--print-uris", f"{PACKAGE_NAME}:{deb_arch}"],
            capture_output=True, text=True, check=True
        )
        # Parse: 'https://...antigravity_1.13.3-123_amd64_hash.deb' antigravity_1.13.3_amd64.deb 12345 SHA256:abc
        match = re.search(r"'([^']+)'", result.stdout)
        if not match:
            return None
        deb_url = match.group(1)
        
        # Extract filename from URL
        filename = deb_url.split("/")[-1]
        
        # Extract file hash from filename: antigravity_1.13.3-123_amd64_HASH.deb
        hash_match = re.search(r'_([a-f0-9]+)\.deb$', filename)
        file_hash = hash_match.group(1) if hash_match else ""
        
    except subprocess.CalledProcessError:
        return None
    
    return {
        "version": version,
        "build_id": build_id,
        "file_hash": file_hash,
        "deb_url": deb_url,
        "deb_arch": deb_arch,
    }


def download_and_checksum(url: str) -> str:
    """Download file and compute SHA256."""
    print(f"  Downloading for checksum...")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    sha256 = hashlib.sha256()
    with urllib.request.urlopen(req, timeout=300) as resp:
        while chunk := resp.read(8192):
            sha256.update(chunk)
    return sha256.hexdigest()


def get_latest_info() -> dict:
    """Fetch latest package info for all architectures."""
    result = {"version": None, "archs": {}}
    
    with tempfile.TemporaryDirectory() as temp_dir:
        # Create required directories
        os.makedirs(f"{temp_dir}/state/lists/partial", exist_ok=True)
        os.makedirs(f"{temp_dir}/cache/archives/partial", exist_ok=True)
        
        for void_arch in ARCH_MAP:
            print(f"Fetching package info for {void_arch}...")
            
            if not setup_apt_repo(temp_dir, void_arch):
                continue
            
            pkg_info = get_package_info_apt(temp_dir, void_arch)
            if not pkg_info:
                print(f"  {void_arch}: Package not found")
                continue
            
            # Get checksum by downloading
            try:
                checksum = download_and_checksum(pkg_info["deb_url"])
            except Exception as e:
                print(f"  {void_arch}: Failed to get checksum: {e}")
                continue
            
            # Construct debfile using template variables
            debfile = '${pkgname}_${version}-' + f'{pkg_info["build_id"]}_{pkg_info["deb_arch"]}_{pkg_info["file_hash"]}.deb'
            
            result["archs"][void_arch] = {
                "debfile": debfile,
                "checksum": checksum,
                "build_id": pkg_info["build_id"],
            }
            
            # Use version from first successful arch
            if result["version"] is None:
                result["version"] = pkg_info["version"]
            
            print(f"  {void_arch}: v{pkg_info['version']} build {pkg_info['build_id']}")
    
    if not result["version"]:
        raise ValueError("Could not find package in any architecture")
    
    return result


def parse_template(content: str) -> dict:
    """Extract current version info from template."""
    version_match = re.search(r'^version=(.+)$', content, re.MULTILINE)
    revision_match = re.search(r'^revision=(\d+)$', content, re.MULTILINE)
    
    # Extract build IDs from debfile patterns (the number after version-)
    x86_build = re.search(r'x86_64\)\s*\n\s*_debfile="[^"]*-(\d+)_amd64', content)
    aarch_build = re.search(r'aarch64\)\s*\n\s*_debfile="[^"]*-(\d+)_arm64', content)
    
    return {
        "version": version_match.group(1) if version_match else None,
        "revision": int(revision_match.group(1)) if revision_match else 1,
        "x86_64": {"build_id": x86_build.group(1) if x86_build else None},
        "aarch64": {"build_id": aarch_build.group(1) if aarch_build else None},
    }


def update_template(content: str, new_info: dict) -> str:
    """Update template content with new version info."""
    version = new_info["version"]
    archs = new_info["archs"]
    
    # Update version and reset revision to 1
    content = re.sub(r'^version=.+$', f'version={version}', content, flags=re.MULTILINE)
    content = re.sub(r'^revision=\d+$', 'revision=1', content, flags=re.MULTILINE)
    
    # Update x86_64 section
    if "x86_64" in archs:
        arch_info = archs["x86_64"]
        content = re.sub(
            r'(x86_64\)\s*\n\s*_debfile=")[^"]+(")',
            f'\\g<1>{arch_info["debfile"]}\\2',
            content
        )
        content = re.sub(
            r'(x86_64\)\s*\n\s*_debfile="[^"]+"\s*\n\s*checksum=")[^"]+(")',
            f'\\g<1>{arch_info["checksum"]}\\2',
            content
        )
    
    # Update aarch64 section
    if "aarch64" in archs:
        arch_info = archs["aarch64"]
        content = re.sub(
            r'(aarch64\)\s*\n\s*_debfile=")[^"]+(")',
            f'\\g<1>{arch_info["debfile"]}\\2',
            content
        )
        content = re.sub(
            r'(aarch64\)\s*\n\s*_debfile="[^"]+"\s*\n\s*checksum=")[^"]+(")',
            f'\\g<1>{arch_info["checksum"]}\\2',
            content
        )
    
    return content


def main():
    print("Checking for antigravity updates...")
    
    # Fetch latest info from APT repo
    try:
        new_info = get_latest_info()
    except Exception as e:
        print(f"Error fetching from APT repo: {e}")
        return 1
    
    print(f"\nLatest version: {new_info['version']}")
    
    # Read current template
    template_content = TEMPLATE_PATH.read_text()
    current = parse_template(template_content)
    print(f"Current version: {current['version']}")
    
    # Compare versions - only update if new version is actually NEWER
    new_ver = version_tuple(new_info["version"])
    cur_ver = version_tuple(current["version"])
    
    if new_ver < cur_ver:
        print(f"\nRemote version {new_info['version']} is OLDER than current {current['version']}. Skipping.")
        return 0
    
    if new_ver == cur_ver:
        # Same version - check if build ID changed
        new_build = new_info["archs"].get("x86_64", {}).get("build_id", "")
        cur_build = current["x86_64"].get("build_id", "")
        
        if new_build == cur_build:
            print("\nAlready up to date!")
            return 0
        
        if new_build and cur_build and int(new_build) <= int(cur_build):
            print(f"\nRemote build {new_build} is not newer than current {cur_build}. Skipping.")
            return 0
        
        print(f"Same version but new build detected ({cur_build} -> {new_build})")
    
    print(f"\nUpdating: {current['version']} -> {new_info['version']}")
    
    # Update template
    updated_content = update_template(template_content, new_info)
    TEMPLATE_PATH.write_text(updated_content)
    
    print(f"Template updated successfully!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
