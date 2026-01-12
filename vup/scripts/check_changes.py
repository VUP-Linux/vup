#!/usr/bin/env python3
import os
import subprocess
import json
import sys
import re

# Import shared config
try:
    from config import SUPPORTED_ARCHS
except ImportError:
    import sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from config import SUPPORTED_ARCHS

def get_changes():
    event = os.environ.get("GITHUB_EVENT_NAME")
    if event == "workflow_dispatch":
        return "ALL"
    
    before = os.environ.get("BEFORE_SHA")
    sha = os.environ.get("GITHUB_SHA")
    
    if not before or before == "0000000000000000000000000000000000000000":
        # forced push or new branch, diff against HEAD~1
        cmd = ["git", "diff", "--name-only", "HEAD~1", "HEAD"]
    else:
        cmd = ["git", "diff", "--name-only", before, sha]
        
    try:
        output = subprocess.check_output(cmd).decode()
    except subprocess.CalledProcessError:
        return "ALL"
        
    return output.splitlines()

def parse_archs_from_template(template_path):
    """
    Parse the 'archs' variable from a template file.
    Returns a list of architectures, or None if not specified.
    """
    try:
        with open(template_path, 'r') as f:
            content = f.read()
        
        # Match archs="..." or archs='...'
        match = re.search(r'^archs=["\']([^"\']+)["\']', content, re.MULTILINE)
        if match:
            archs_str = match.group(1)
            # Split by whitespace and filter out negated archs (starting with ~)
            archs = [a for a in archs_str.split() if not a.startswith('~') and a != 'noarch']
            return archs if archs else None
    except Exception as e:
        print(f"Warning: Could not parse {template_path}: {e}")
    
    return None

def get_category_archs(category_path):
    """
    Scan all packages in a category and return the union of all architectures needed.
    """
    archs = set()
    
    if not os.path.isdir(category_path):
        return SUPPORTED_ARCHS
    
    packages = [d for d in os.listdir(category_path) 
                if os.path.isdir(os.path.join(category_path, d))]
    
    for pkg in packages:
        template_path = os.path.join(category_path, pkg, "template")
        if os.path.exists(template_path):
            pkg_archs = parse_archs_from_template(template_path)
            if pkg_archs:
                archs.update(pkg_archs)
            else:
                # No archs specified means it builds for all supported
                archs.update(SUPPORTED_ARCHS)
    
    return sorted(list(archs)) if archs else SUPPORTED_ARCHS

def main():
    changes = get_changes()
    # Dynamically find categories in vup/srcpkgs
    if not os.path.exists("vup/srcpkgs"):
        print("vup/srcpkgs not found")
        sys.exit(0)
        
    all_cats = [d for d in os.listdir("vup/srcpkgs") if os.path.isdir(os.path.join("vup/srcpkgs", d))]
    
    target_cats = set()
    if changes == "ALL":
        target_cats = set(all_cats)
    else:
        for f in changes:
            # Check for global changes
            if f.startswith("common/") or f.startswith("vup/common/") or f.startswith(".github/workflows/"):
                target_cats = set(all_cats)
                break
                
            # Check for category changes
            # Expected path: vup/srcpkgs/<category>/<pkg>/...
            if f.startswith("vup/srcpkgs/"):
                parts = f.split("/")
                if len(parts) > 2 and parts[2] in all_cats:
                    target_cats.add(parts[2])
    
    target_list = sorted(list(target_cats))
    
    output_file = os.environ.get("GITHUB_OUTPUT")
    
    if not target_list:
        print("No changes detected.")
        if output_file:
            with open(output_file, "a") as gh:
                gh.write("should_run=false\n")
                gh.write('matrix={"include":[]}\n')
    else:
        # Build matrix with category + arch combinations
        includes = []
        for cat in target_list:
            cat_path = os.path.join("vup/srcpkgs", cat)
            archs = get_category_archs(cat_path)
            print(f"Category '{cat}' needs architectures: {archs}")
            for arch in archs:
                includes.append({"category": cat, "arch": arch})
        
        print(f"Total build jobs: {len(includes)}")
        matrix_json = json.dumps({"include": includes})
        if output_file:
            with open(output_file, "a") as gh:
                gh.write("should_run=true\n")
                gh.write(f"matrix={matrix_json}\n")

if __name__ == "__main__":
    main()
