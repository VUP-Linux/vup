#!/usr/bin/env python3
import os
import sys
import subprocess
import json
import shutil
import glob
import time
import re

# Import shared config
try:
    from config import NATIVE_ARCH, parse_template_archs, arch_supported
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from config import NATIVE_ARCH, parse_template_archs, arch_supported


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


def parse_template_depends(template_path):
    """Parse depends and makedepends from a template file."""
    deps = set()
    
    try:
        with open(template_path, 'r') as f:
            content = f.read()
        
        # Match depends="..." or makedepends="..."
        for field in ['depends', 'makedepends', 'hostmakedepends']:
            match = re.search(rf'^{field}=["\']([^"\']+)["\']', content, re.MULTILINE)
            if match:
                # Split on whitespace and extract base package name (strip version constraints)
                for dep in match.group(1).split():
                    # Remove version constraints like >=1.0
                    base_dep = re.split(r'[<>=]', dep)[0]
                    if base_dep:
                        deps.add(base_dep)
    except Exception as e:
        print(f"Warning: Could not parse template {template_path}: {e}")
    
    return deps


def install_vup_deps(pkg_name, template_path, category, arch):
    """
    Check if package has dependencies that exist in VUP and install them.
    This enables building packages that depend on other VUP packages.
    """
    # Check if vuru is available
    if not shutil.which("vuru"):
        print(f"[{pkg_name}] vuru not found, skipping VUP dependency resolution")
        return True
    
    deps = parse_template_depends(template_path)
    if not deps:
        return True
    
    print(f"[{pkg_name}] Checking {len(deps)} dependencies against VUP index...")
    
    # Sync vuru index
    subprocess.run(["vuru", "-S"], capture_output=True)
    
    # Check each dep against VUP index using vuru query
    vup_deps = []
    for dep in deps:
        result = subprocess.run(
            ["vuru", "query", dep],
            capture_output=True,
            text=True
        )
        # If vuru finds it and it says "Source: VUP", it's a VUP package
        if result.returncode == 0 and "Source: VUP" in result.stdout:
            # Check if already installed
            installed_check = subprocess.run(
                ["xbps-query", dep],
                capture_output=True
            )
            if installed_check.returncode != 0:
                vup_deps.append(dep)
    
    if not vup_deps:
        print(f"[{pkg_name}] No VUP dependencies to install")
        return True
    
    print(f"[{pkg_name}] Installing VUP dependencies: {', '.join(vup_deps)}")
    
    # Install each VUP dependency
    for dep in vup_deps:
        result = subprocess.run(
            ["vuru", "-y", dep],
            capture_output=False  # Show output for debugging
        )
        if result.returncode != 0:
            print(f"[{pkg_name}] Warning: Failed to install VUP dep {dep}")
            # Continue anyway - the dep might be optional or satisfied another way
    
    return True

def main():
    category = os.environ.get("CATEGORY")
    if not category:
        print("Error: CATEGORY environment variable not set.")
        sys.exit(1)
    
    arch = os.environ.get("ARCH", NATIVE_ARCH)
    print(f"Building for architecture: {arch}")

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

    all_packages = [p for p in os.listdir(vup_src_path) if os.path.isdir(os.path.join(vup_src_path, p))]
    all_packages.sort()

    packages_env = os.environ.get("PACKAGES", "ALL")
    if packages_env == "ALL":
        packages = all_packages
    else:
        whitelist = set(packages_env.split())
        packages = [p for p in all_packages if p in whitelist]

    print(f"Found {len(packages)} packages to build in {category}: {', '.join(packages)}")

    for pkg in packages:
        pkg_src = os.path.join(vup_src_path, pkg)
        pkg_dest = os.path.join("srcpkgs", pkg)
        log_file = f"build-logs/{pkg}.log"
        
        # Check if this package supports the target architecture
        template_path = os.path.join(pkg_src, "template")
        pkg_archs = parse_template_archs(template_path)
        
        if not arch_supported(pkg_archs, arch):
            print(f"[{pkg}] Skipping - not supported on {arch} (archs: {pkg_archs})")
            continue
        
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

        # Install any VUP dependencies before building
        install_vup_deps(pkg, template_path, category, arch)

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
