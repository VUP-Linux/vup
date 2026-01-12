#!/usr/bin/env python3
"""
Generate a unified build summary from multiple report JSON files.
Aggregates results by package across categories and architectures.
"""
import sys
import json
import os
import glob
from collections import defaultdict

def main():
    # Find all report files in the reports directory
    report_dir = sys.argv[1] if len(sys.argv) > 1 else "reports"
    report_files = glob.glob(os.path.join(report_dir, "*.json"))
    
    if not report_files:
        print("No report files found.")
        return
    
    # Structure: {category: {package: {arch: {status, duration, error_log}}}}
    aggregated = defaultdict(lambda: defaultdict(dict))
    
    for report_file in report_files:
        try:
            with open(report_file, 'r') as f:
                data = json.load(f)
            
            cat = data.get("category", "unknown")
            arch = data.get("arch", "unknown")
            results = data.get("results", [])
            
            for r in results:
                name = r.get("name", "unknown")
                aggregated[cat][name][arch] = {
                    "status": r.get("status", "unknown"),
                    "duration": r.get("duration", 0),
                    "error_log": r.get("error_log", "")
                }
        except Exception as e:
            print(f"Warning: Could not parse {report_file}: {e}")
    
    if not aggregated:
        print("No valid reports found.")
        return
    
    # Collect all architectures seen
    all_archs = set()
    for cat_data in aggregated.values():
        for pkg_data in cat_data.values():
            all_archs.update(pkg_data.keys())
    all_archs = sorted(all_archs)
    
    # Store errors to print after tables
    errors = []
    
    # Generate summary per category
    for cat in sorted(aggregated.keys()):
        packages = aggregated[cat]
        
        print(f"## Category: `{cat}`")
        print()
        
        # Build header with arch columns
        header = "| Package |"
        separator = "|---------|"
        for arch in all_archs:
            header += f" {arch} |"
            separator += "----------|"
        
        print(header)
        print(separator)
        
        for pkg in sorted(packages.keys()):
            arch_results = packages[pkg]
            row = f"| {pkg} |"
            
            for arch in all_archs:
                if arch in arch_results:
                    result = arch_results[arch]
                    status = result["status"]
                    duration = result["duration"]
                    
                    if status == "success":
                        row += f" ✅ {duration:.1f}s |"
                    else:
                        row += f" ❌ {duration:.1f}s |"
                        # Collect error for later
                        if result.get("error_log"):
                            errors.append({
                                "category": cat,
                                "package": pkg,
                                "arch": arch,
                                "log": result["error_log"]
                            })
                else:
                    row += " — |"  # Not built for this arch
                        
        print()
    
    # Print errors after all tables (so they don't break table formatting)
    if errors:
        print("---")
        print("## Build Errors")
        print()
        for err in errors:
            print(f"<details>")
            print(f"<summary>❌ {err['package']} ({err['category']}/{err['arch']})</summary>")
            print()
            print("```")
            # Sanitize log content - remove any pipe characters that might break markdown
            log = err['log'].replace('|', '¦')
            print(log)
            print("```")
            print()
            print("</details>")
            print()

if __name__ == "__main__":
    main()
