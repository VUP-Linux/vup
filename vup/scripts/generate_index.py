#!/usr/bin/env python3
import os
import json
import re

# Import shared config
try:
    from config import SUPPORTED_ARCHS, BASE_URL, SRCPKGS_DIR, parse_template_archs, get_positive_archs
except ImportError:
    import sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from config import SUPPORTED_ARCHS, BASE_URL, SRCPKGS_DIR, parse_template_archs, get_positive_archs

def parse_template(template_path):
    """
    Parses a void-linux template file to extract version and revision.
    Very basic regex parsing - in a real scenario, could source the file.
    """
    version = None
    revision = None
    
    with open(template_path, 'r') as f:
        content = f.read()
        
        # Regex for version and revision
        # Note: This handles simple 'version=1.2.3' and 'revision=1'
        # It does NOT handle variable substitution like 'version=${_ver}'
        v_match = re.search(r'^version=([^\s#]+)', content, re.MULTILINE)
        r_match = re.search(r'^revision=([^\s#]+)', content, re.MULTILINE)
        
        if v_match:
            version = v_match.group(1).strip('"\'')
        if r_match:
            revision = r_match.group(1).strip('"\'')
            
    return version, revision

def generate_index():
    index = {}
    
    # categories are top-level dirs in srcpkgs
    if not os.path.isdir(SRCPKGS_DIR):
        print(f"Error: {SRCPKGS_DIR} not found.")
        return

    categories = sorted([d for d in os.listdir(SRCPKGS_DIR) 
                 if os.path.isdir(os.path.join(SRCPKGS_DIR, d))])
    
    for category in categories:
        cat_dir = os.path.join(SRCPKGS_DIR, category)
        packages = sorted([d for d in os.listdir(cat_dir) 
                   if os.path.isdir(os.path.join(cat_dir, d))])
        
        for pkg in packages:
            template_path = os.path.join(cat_dir, pkg, "template")
            if not os.path.exists(template_path):
                continue
                
            version, revision = parse_template(template_path)
            
            if version and revision:
                full_version = f"{version}_{revision}"
                
                # Parse archs from template using shared function
                raw_archs = parse_template_archs(template_path)
                archs = get_positive_archs(raw_archs)
                if not archs:
                    archs = SUPPORTED_ARCHS.copy()
                
                # Build repo_urls dict per architecture
                repo_urls = {}
                for arch in archs:
                    repo_urls[arch] = f"{BASE_URL}/{category}-{arch}-current"
                
                index[pkg] = {
                    "category": category,
                    "version": full_version,
                    "archs": archs,
                    "repo_urls": repo_urls
                }
                print(f"Indexed: {pkg} -> {category} ({full_version}) [{', '.join(archs)}]")
            else:
                print(f"Warning: Could not parse version/revision for {pkg}")

    # Output to public/index.json
    os.makedirs("public", exist_ok=True)
    with open("public/index.json", "w") as f:
        json.dump(index, f, indent=2)
    print("Generated public/index.json")

if __name__ == "__main__":
    generate_index()
