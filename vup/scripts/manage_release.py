#!/usr/bin/env python3
"""
Download and clean GitHub release assets for VUP repositories.
"""

import glob
import json
import os
import subprocess
import sys
from typing import Literal, overload

# Configuration from environment
REPO: str = os.environ.get("GITHUB_REPOSITORY", "")
CATEGORY: str = os.environ.get("CATEGORY", "")
ARCH: str = os.environ.get("ARCH", "x86_64")
TAG_NAME: str = f"{CATEGORY}-{ARCH}-current"
DIST_DIR: str = "dist"


@overload
def run_command(cmd: list[str], capture_output: Literal[True]) -> str | None: ...


@overload
def run_command(cmd: list[str], capture_output: Literal[False] = False) -> bool | None: ...


def run_command(cmd: list[str], capture_output: bool = False) -> str | bool | None:
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
        print("Usage: manage_release.py [download|clean_remote]")
        print()
        print("Commands:")
        print("  download     - Download existing release assets from GitHub")
        print("  clean_remote - Delete obsolete assets from GitHub release")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "download":
        download_release()
    elif cmd == "clean_remote":
        clean_remote_assets()
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)
