#!/usr/bin/env python3
import sys
import json
import os

def main():
    try:
        # Check if stdin has data
        if sys.stdin.isatty():
            return

        data = json.load(sys.stdin)
        cat = data["category"]
        results = data["results"]
        
        print(f"## Category: {cat}")
        print("| Package | Status | Duration |")
        print("|---------|--------|----------|")
        
        for r in results:
            icon = "✅" if r["status"] == "success" else "❌"
            duration = r.get("duration", 0)
            dur = f"{duration:.1f}s"
            name = r["name"]
            status = r["status"]
            print(f"| {name} | {icon} {status} | {dur} |")
            
            if status == "failure":
                print("<details>")
                print(f"<summary>Error Log: {name}</summary>")
                print("\n```")
                print(r.get("error_log", "No log captured"))
                print("```\n")
                print("</details>")
                
    except Exception as e:
        print(f"Error generating summary: {e}")

if __name__ == "__main__":
    main()
