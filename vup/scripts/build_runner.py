#!/usr/bin/env python3
import os
import sys
import subprocess
import json
import shutil
import glob
import time

# Import shared config
try:
    from config import NATIVE_ARCH
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from config import NATIVE_ARCH

def run_command(cmd, log_file=None):
    """Run a command and capture output to log_file if provided."""
    print(f"Running: {' '.join(cmd)}")
    
    if log_file:
        with open(log_file, "w") as f:
            try:
                # Pipe stdout/stderr to both file and current stdout
                process = subprocess.Popen(
                    cmd, 
                    stdout=subprocess.PIPE, 
                    stderr=subprocess.STDOUT, 
                    text=True
                )
                
                for line in process.stdout:
                    sys.stdout.write(line)
                    f.write(line)
                
                process.wait()
                return process.returncode == 0
            except Exception as e:
                f.write(f"\nError executing command: {e}\n")
                return False
    else:
        return subprocess.call(cmd) == 0

def main():
    category = os.environ.get("CATEGORY")
    if not category:
        print("Error: CATEGORY environment variable not set.")
        sys.exit(1)
    
    arch = os.environ.get("ARCH", NATIVE_ARCH)
    print(f"Building for architecture: {arch}"))

    # Assumes we are running from 'void-packages' directory
    # and vup checkout is at '../vup'
    vup_src_path = f"../vup/vup/srcpkgs/{category}"
    
    if not os.path.exists(vup_src_path):
        print(f"Category path {vup_src_path} does not exist.")
        # If category is missing but explicitly requested, maybe it was deleted?
        # Just report nothing built.
        report = {"category": category, "results": []}
        with open(f"report-{category}.json", "w") as f:
            json.dump(report, f)
        sys.exit(0)

    results = []
    
    # Ensure logs directory exists
    os.makedirs("build-logs", exist_ok=True)

    packages = [p for p in os.listdir(vup_src_path) if os.path.isdir(os.path.join(vup_src_path, p))]
    packages.sort()

    print(f"Found {len(packages)} packages in {category}: {', '.join(packages)}")

    for pkg in packages:
        pkg_src = os.path.join(vup_src_path, pkg)
        pkg_dest = os.path.join("srcpkgs", pkg)
        log_file = f"build-logs/{pkg}.log"
        
        result_entry = {
            "name": pkg,
            "status": "pending",
            "start_time": time.time()
        }

        print(f"[{pkg}] Setup...")
        # Clean previous overlay
        if os.path.exists(pkg_dest):
            shutil.rmtree(pkg_dest)
        
        # Copy new template
        shutil.copytree(pkg_src, pkg_dest)

        print(f"[{pkg}] Building for {arch}...")
        # Use -a flag for cross-compilation if not native arch
        if arch == NATIVE_ARCH:
            build_cmd = ["./xbps-src", "pkg", pkg]
        else:
            build_cmd = ["./xbps-src", "-a", arch, "pkg", pkg]
        success = run_command(build_cmd, log_file=log_file)
        
        result_entry["end_time"] = time.time()
        result_entry["duration"] = result_entry["end_time"] - result_entry["start_time"]
        
        if success:
            print(f"[{pkg}] Build SUCCESS")
            result_entry["status"] = "success"
        else:
            print(f"[{pkg}] Build FAILED")
            result_entry["status"] = "failure"
            
            # Extract last 30 lines of log for summary
            try:
                with open(log_file, "r") as f:
                    lines = f.readlines()
                    result_entry["error_log"] = "".join(lines[-30:])
            except:
                result_entry["error_log"] = "Could not read log file."

        # Clean up
        if os.path.exists(pkg_dest):
            shutil.rmtree(pkg_dest)

        # Move binpkgs on success
        if success:
            found_bins = []
            # Recursively find all binpkgs for this package
            for root, dirs, files in os.walk("hostdir/binpkgs"):
                for file in files:
                    if file.startswith(f"{pkg}-") and file.endswith(".xbps"):
                        found_bins.append(os.path.join(root, file))

            os.makedirs("dist", exist_ok=True)
            for b in found_bins:
                 print(f"[{pkg}] Found binary: {b}")
                 shutil.copy2(b, "dist/")
                 
        results.append(result_entry)

    # Write Report
    report = {
        "category": category,
        "arch": arch,
        "results": results
    }
    
    with open(f"report-{category}-{arch}.json", "w") as f:
        json.dump(report, f, indent=2)

if __name__ == "__main__":
    main()
