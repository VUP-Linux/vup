#!/usr/bin/env python3
"""
Shared configuration for VUP build scripts.
Edit these values to customize supported architectures and other settings.
"""

# Supported architectures for building
# These are used as defaults when a template doesn't specify archs
SUPPORTED_ARCHS = ["x86_64"]

# The native architecture of the build runner (no cross-compile flag needed)
NATIVE_ARCH = "x86_64"

# GitHub repository info
REPO_OWNER = "VUP-Linux"
REPO_NAME = "vup"
BASE_URL = f"https://github.com/{REPO_OWNER}/{REPO_NAME}/releases/download"

# Path to srcpkgs relative to repo root
SRCPKGS_DIR = "vup/srcpkgs"
