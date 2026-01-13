#!/usr/bin/env python3
"""
Auto-updater for antigravity package.
Fetches version info from the APT repository metadata.
"""

import re
import sys
import gzip
import urllib.request
from pathlib import Path

TEMPLATE_PATH = Path(__file__).parent.parent.parent / "srcpkgs/editors/antigravity/template"

# APT repository configuration
REPO_BASE = "https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev"
DIST = "antigravity-debian"
COMPONENT = "main"
PACKAGE_NAME = "antigravity"

# Map void arch to debian arch
ARCH_MAP = {
    "x86_64": "amd64",
    "aarch64": "arm64",
}


def fetch_packages_file(arch: str) -> str:
    """Fetch and decompress the Packages file for an architecture."""
    deb_arch = ARCH_MAP[arch]
    # Try gzipped first, fall back to plain
    for ext, decompress in [(".gz", True), ("", False)]:
        url = f"{REPO_BASE}/dists/{DIST}/{COMPONENT}/binary-{deb_arch}/Packages{ext}"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = resp.read()
                if decompress:
                    return gzip.decompress(data).decode("utf-8")
                return data.decode("utf-8")
        except urllib.error.HTTPError:
            continue
    raise ValueError(f"Could not fetch Packages file for {arch}")


def parse_packages_file(content: str, package_name: str) -> dict | None:
    """
    Parse APT Packages file and extract info for the specified package.
    Returns dict with version, filename, sha256.
    """
    # Split into package entries
    entries = content.split("\n\n")
    
    for entry in entries:
        lines = entry.strip().split("\n")
        pkg_data = {}
        for line in lines:
            if ": " in line:
                key, value = line.split(": ", 1)
                pkg_data[key] = value
        
        if pkg_data.get("Package") == package_name:
            version_full = pkg_data.get("Version", "")
            # Version format: 1.13.3-1766182170 (version-buildid)
            version = version_full.split("-")[0] if "-" in version_full else version_full
            build_id = version_full.split("-")[1] if "-" in version_full else ""
            
            # Extract the file hash from filename
            # Format: antigravity_1.13.3-1766182170_amd64_365061c50063f9bd47a9ff88432261b8.deb
            filename = pkg_data.get("Filename", "")
            file_hash_match = re.search(r'_([a-f0-9]+)\.deb$', filename)
            file_hash = file_hash_match.group(1) if file_hash_match else ""
            
            # Extract deb arch from filename
            deb_arch_match = re.search(r'_(amd64|arm64)_', filename)
            deb_arch = deb_arch_match.group(1) if deb_arch_match else ""
            
            return {
                "version": version,
                "build_id": build_id,
                "file_hash": file_hash,
                "deb_arch": deb_arch,
                "sha256": pkg_data.get("SHA256", ""),
            }
    
    return None


def get_latest_info() -> dict:
    """Fetch latest package info for all architectures from APT repo."""
    result = {"version": None, "archs": {}}
    
    for void_arch in ARCH_MAP:
        print(f"Fetching package info for {void_arch}...")
        try:
            packages_content = fetch_packages_file(void_arch)
            pkg_info = parse_packages_file(packages_content, PACKAGE_NAME)
            
            if pkg_info:
                # Construct debfile using template variables for pkgname and version
                # Format: ${pkgname}_${version}-BUILDID_ARCH_HASH.deb
                debfile = '${pkgname}_${version}-' + f'{pkg_info["build_id"]}_{pkg_info["deb_arch"]}_{pkg_info["file_hash"]}.deb'
                
                result["archs"][void_arch] = {
                    "debfile": debfile,
                    "checksum": pkg_info["sha256"],
                }
                
                # Use version from first successful arch
                if result["version"] is None:
                    result["version"] = pkg_info["version"]
                
                print(f"  {void_arch}: v{pkg_info['version']} build {pkg_info['build_id']}")
            else:
                print(f"  {void_arch}: Package not found in repo")
                
        except Exception as e:
            print(f"  {void_arch}: Error - {e}")
    
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
    
    # Compare - check both version and build_id (in case of rebuild)
    if new_info["version"] == current["version"]:
        # Extract build_id from the new info for comparison
        new_build = new_info["archs"].get("x86_64", {}).get("debfile", "")
        new_build_match = re.search(r'-(\d+)_amd64', new_build)
        new_build_id = new_build_match.group(1) if new_build_match else ""
        cur_build_id = current["x86_64"].get("build_id", "")
        
        if new_build_id == cur_build_id:
            print("\nAlready up to date!")
            return 0
        print(f"Same version but new build detected ({cur_build_id} -> {new_build_id})")
    
    print(f"\nUpdating: {current['version']} -> {new_info['version']}")
    
    # Update template
    updated_content = update_template(template_content, new_info)
    TEMPLATE_PATH.write_text(updated_content)
    
    print(f"Template updated successfully!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
