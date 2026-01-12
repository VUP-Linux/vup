#!/usr/bin/env python3
import os
import subprocess
import json
import sys

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
                gh.write("matrix={\"category\":[]}\n")
    else:
        print(f"Building categories: {target_list}")
        matrix_json = json.dumps({"category": target_list})
        if output_file:
            with open(output_file, "a") as gh:
                gh.write("should_run=true\n")
                gh.write(f"matrix={matrix_json}\n")

if __name__ == "__main__":
    main()
