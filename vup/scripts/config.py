#!/usr/bin/env python3
"""
Shared configuration for VUP build scripts.
Edit these values to customize supported architectures and other settings.
"""
import re

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


def parse_template_archs(template_path):
    """
    Parse the 'archs' field from a template file.
    Returns a list of supported architectures, or None if not specified (means all archs).
    """
    try:
        with open(template_path, 'r') as f:
            content = f.read()
        
        # Match archs="..." or archs='...'
        match = re.search(r'^archs=["\']([^"\']+)["\']', content, re.MULTILINE)
        if match:
            archs_str = match.group(1)
            return archs_str.split()
    except Exception as e:
        print(f"Warning: Could not parse template {template_path}: {e}")
    
    return None  # No archs specified = builds for all


def arch_supported(archs_list, target_arch):
    """
    Check if target_arch is supported given the archs list from template.
    Handles negation (~arch) and 'noarch'.
    """
    if archs_list is None:
        return True  # No restriction
    
    # Check for noarch
    if "noarch" in archs_list:
        return True
    
    # Check for negations
    negated = [a[1:] for a in archs_list if a.startswith('~')]
    if negated:
        # If there are negations, arch is supported unless explicitly negated
        return target_arch not in negated
    
    # Positive list - arch must be in it
    return target_arch in archs_list


def get_positive_archs(archs_list):
    """
    Get list of positive (non-negated) architectures from archs list.
    Returns None if no archs specified, or SUPPORTED_ARCHS if only negations.
    """
    if archs_list is None:
        return None
    
    # Filter out negated and noarch
    positive = [a for a in archs_list if not a.startswith('~') and a != 'noarch']
    
    if positive:
        return positive
    
    # Only negations or noarch - means all supported minus negated
    if "noarch" in archs_list:
        return None  # noarch means all
    
    return None  # Only negations, treat as "all supported"
