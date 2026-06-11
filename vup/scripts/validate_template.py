#!/usr/bin/env python3
"""
Validate VUP package templates for required fields.
Usage: python3 validate_template.py [template_paths...]

Returns exit code 1 if any template fails validation.
"""
import re
import sys
import os

REQUIRED_FIELDS = [
    "pkgname",
    "version",
    "revision",
    "license",
    "homepage",
    "distfiles",
    "short_desc",
    "maintainer",
]

# Fields that can legitimately be empty for subpackages or special templates
OPTIONAL_FIELDS = [
    "build_style",
    "depends",
    "checksum",
    "archs",
    "noshlibprovides",
    "nopie",
    "nostrip",
    "restricted",
    "create_wrksrc",
    "skip_extraction",
    "hostmakedepends",
    "makedepends",
]


def parse_template(path):
    """Parse a template file and return a dict of field -> value."""
    fields = {}
    try:
        with open(path, "r") as f:
            content = f.read()
    except Exception as e:
        print(f"ERROR: Cannot read {path}: {e}")
        return None

    # Match shell variable assignments at any indentation level.
    # Required fields may be inside case/esac blocks (e.g. distfiles).
    pattern = re.compile(r'^\s*(\w+)=(.*)', re.MULTILINE)
    for match in pattern.finditer(content):
        key = match.group(1)
        value = match.group(2).strip()
        # Strip quotes if present
        if (value.startswith('"') and value.endswith('"')) or \
           (value.startswith("'") and value.endswith("'")):
            value = value[1:-1]
        # For multi-line values (ending with "), just record presence
        fields[key] = value if value else "(empty)"

    return fields


def check_noshlibprovides(fields, raw_content, path):
    """Warn if the template looks like an Electron/prebuilt app without noshlibprovides."""
    pkgname = fields.get("pkgname", "")
    short_desc = fields.get("short_desc", "").lower()
    homepage = fields.get("homepage", "").lower()
    distfiles = fields.get("distfiles", "").lower()

    # If it has build_style or do_build(), it's compiled from source — no warning needed
    if fields.get("build_style", ""):
        return None
    if "do_build()" in raw_content:
        return None

    # Heuristics for prebuilt/electron apps
    prebuilt_indicators = [
        ".tar.gz" in distfiles or ".zip" in distfiles,
        "browser" in short_desc or "browser" in pkgname,
        "editor" in short_desc or "ide" in short_desc,
        "electron" in pkgname or "electron" in short_desc,
    ]

    if any(prebuilt_indicators):
        if "noshlibprovides" not in fields:
            return f"WARNING: {pkgname} looks like a prebuilt app. Consider adding noshlibprovides=yes to prevent bundled library pollution."

    return None


def validate_template(path):
    """Validate a single template. Returns (ok: bool, messages: list[str])."""
    messages = []
    pkg_dir = os.path.basename(os.path.dirname(path))

    fields = parse_template(path)
    if fields is None:
        return False, [f"ERROR: {path}: Cannot parse template"]

    # Read raw content for checks that need full text
    try:
        with open(path, "r") as f:
            raw_content = f.read()
    except Exception:
        raw_content = ""

    pkgname = fields.get("pkgname", "")
    if pkgname and pkgname != pkg_dir:
        messages.append(
            f"WARNING: {path}: pkgname={pkgname} does not match directory name '{pkg_dir}'"
        )

    all_ok = True
    skip_distfiles = fields.get("bootstrap", "") == "yes"

    for field in REQUIRED_FIELDS:
        if field == "distfiles" and skip_distfiles:
            continue
        if field not in fields or not fields[field].strip():
            messages.append(f"ERROR: {path}: Missing required field '{field}'")
            all_ok = False

    # version should not be empty/devel unless it's a -devel template
    if "version" in fields and fields["version"] in ("", "(empty)"):
        messages.append(f"ERROR: {path}: version is empty")
        all_ok = False

    # revision should be a number
    if "revision" in fields:
        try:
            int(fields["revision"])
        except (ValueError, TypeError):
            messages.append(f"ERROR: {path}: revision must be an integer, got '{fields['revision']}'")
            all_ok = False

    # noshlibprovides heuristic check
    noshlib_warn = check_noshlibprovides(fields, raw_content, path)
    if noshlib_warn:
        messages.append(noshlib_warn)

    return all_ok, messages


def main():
    if len(sys.argv) < 2:
        print("Usage: validate_template.py <template_path> [template_path ...]")
        sys.exit(0)

    all_ok = True
    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            print(f"ERROR: {path}: File not found")
            all_ok = False
            continue

        ok, messages = validate_template(path)
        for msg in messages:
            print(msg)
        if not ok:
            all_ok = False
        elif not messages:
            pkgname = os.path.basename(os.path.dirname(path))
            print(f"OK: {pkgname}")

    if not all_ok:
        print("\nValidation FAILED. Fix the errors above before submitting your PR.")
        sys.exit(1)
    else:
        print("\nAll templates passed validation.")
        sys.exit(0)


if __name__ == "__main__":
    main()
