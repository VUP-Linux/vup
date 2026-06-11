#!/usr/bin/env python3
"""
Analyze PR build reports and generate a markdown comment for the VUP bot.
Replaces the inline Python heredoc in vup-bot.yml.

Usage: python3 analyze_pr_report.py --reports-dir reports --run-url <url> --output comment.md
"""
import os
import sys
import json
import glob
import argparse
import html


def analyze(reports_dir, run_url):
    reports = glob.glob(os.path.join(reports_dir, "*.json"))
    summary = []
    failures = 0

    print("Scanning reports...")

    for r in reports:
        try:
            with open(r, "r") as f:
                data = json.load(f)
                summary.extend(data)
                for res in data:
                    if res.get("status") == "failure":
                        failures += 1
        except Exception as e:
            print(f"Error reading {r}: {e}")

    md = ""

    if failures == 0:
        md += "### :white_check_mark: VUP Build Passed\n\n"
        md += f"Built {len(summary)} packages successfully. [View Logs]({run_url})\n"
    else:
        md += f"### :x: {failures} VUP Build Failed\n\n"
        md += f"[View Full Logs]({run_url})\n\n"

    if len(summary) > 0:
        md += "| Package | Status |\n"
        md += "|---------|--------|\n"
        for res in summary:
            icon = ":white_check_mark:" if res.get("status") == "success" else ":x:"
            pkg_name = res.get("package", "unknown")
            status = res.get("status", "unknown")
            md += f"| {pkg_name} | {icon} {status} |\n"

        failures_list = [r for r in summary if r.get("status") == "failure"]
        if failures_list:
            md += "\n<br>\n\n### :mag: Failure Details\n"
            md += f"[Download full build logs]({run_url})\n"
            for res in failures_list:
                pkg = res.get("package")
                log = res.get("log", "No log available")
                log = html.escape(log)
                md += f"\n<details><summary><strong>{pkg}</strong> Build Log</summary>\n\n<pre>{log}</pre>\n</details>\n"
    else:
        md += "No packages were modified or built in this run."

    return md, failures


def main():
    parser = argparse.ArgumentParser(description="Analyze PR build reports")
    parser.add_argument("--reports-dir", default="reports", help="Directory containing report JSON files")
    parser.add_argument("--run-url", required=True, help="URL to the CI run for linking")
    parser.add_argument("--output", default="comment.md", help="Output markdown file")
    args = parser.parse_args()

    md, failures = analyze(args.reports_dir, args.run_url)

    with open(args.output, "w") as f:
        f.write(md)

    print(f"Generated {args.output} ({failures} failures)")

    # Set outputs for GitHub Actions
    gh_output = os.environ.get("GITHUB_OUTPUT")
    if gh_output:
        with open(gh_output, "a") as fh:
            if failures > 0:
                fh.write("result=failure\n")
            else:
                fh.write("result=success\n")


if __name__ == "__main__":
    main()
