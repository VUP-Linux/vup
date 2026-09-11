#!/usr/bin/env python3
"""Isolated CLI regression tests; no network, root access or XBPS required.

Usage: python3 tests/install_modes.py /path/to/vuru
"""
import json
import os
from pathlib import Path
import pty
import select
import subprocess
import sys
import tempfile
import time

binary = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix="vuru-modes-") as tmp:
    root = Path(tmp)
    home = root / "home with spaces"
    home.mkdir()
    config = root / "config" / "vuru" / "config.conf"
    cache = root / "cache" / "vup"
    cache.mkdir(parents=True)
    packages = {
        "demo": {"version": "1.0_1", "category": "apps", "repo_urls": {"x86_64": "https://example.test/repo", "aarch64": "https://example.test/repo"}},
        "source-only": {"version": "1.0_1", "category": "apps", "repo_urls": {}},
        "parent": {"version": "2.0_1", "category": "apps", "repo_urls": {}},
        "child": {"version": "3.0_1", "category": "libs", "repo_urls": {}},
    }
    (cache / "index.json").write_text(json.dumps({"packages": packages}))
    mockbin = root / "bin"
    mockbin.mkdir()
    log = root / "commands.jsonl"
    mock = mockbin / "mock"
    mock.write_text("""#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['VURU_TEST_LOG'], 'a') as f:
    f.write(json.dumps([name, *args]) + '\\n')
if name == os.environ.get('VURU_TEST_FAIL'): sys.exit(1)
if name == 'xbps-query':
    if os.environ.get('VURU_TEST_UPDATE'):
        if args == ['-l']:
            print('ii demo-0.9_1 package')
            print('ii source-only-0.9_1 package')
            sys.exit(0)
        if args == ['demo']:
            print('pkgver: demo-0.9_1')
            sys.exit(0)
    sys.exit(1)
if name == 'xbps-uhelper' and args[:1] == ['cmpver']:
    sys.exit(1)
if name == 'curl':
    output = pathlib.Path(args[args.index('-o') + 1])
    if args[-1].endswith('index.json'):
        output.write_text(os.environ['VURU_TEST_INDEX_JSON'])
    elif '/parent/template' in args[-1]:
        output.write_text('pkgname=parent\\nversion=2.0\\nrevision=1\\ndepends="child"\\n')
    else:
        output.write_text('pkgname=demo\\nversion=1.0\\nrevision=1\\n')
if name == 'git':
    dest = pathlib.Path(args[-1]) / 'vup'
    dest.mkdir(parents=True)
    (dest / 'common/xbps-src/shutils').mkdir(parents=True)
    (dest / 'common/xbps-src/shutils/vuru_local_dependencies.sh').write_text('vuru_official_repositories() { echo https://repo-default.voidlinux.org/current; }')
    (dest / 'xbps-src').symlink_to(os.environ['VURU_TEST_MOCK'])
    for pkg in ('demo', 'source-only'):
        template = dest / 'srcpkgs/apps' / pkg / 'template'
        template.parent.mkdir(parents=True)
        template.write_text('pkgname=' + pkg)
    (dest / 'hostdir/binpkgs/apps').mkdir(parents=True)
if name == 'xbps-src' and args == ['binary-bootstrap']:
    master = pathlib.Path(sys.argv[0]).parent / 'masterdir'
    master.mkdir(exist_ok=True)
    (master / '.xbps_chroot_init').write_text('x86_64')
""")
    mock.chmod(0o755)
    for name in ("xbps-query", "xbps-uhelper", "curl", "git", "sudo"):
        (mockbin / name).symlink_to(mock)
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(root / "config"),
               XDG_CACHE_HOME=str(root / "cache"), PATH=f"{mockbin}:{os.environ['PATH']}",
               VURU_TEST_LOG=str(log), VURU_TEST_MOCK=str(mock),
               VURU_TEST_INDEX_JSON=json.dumps({"packages": packages}))

    def run(*args, success=True):
        result = subprocess.run([binary, *args], env=env, input="", text=True, capture_output=True, timeout=10)
        assert (result.returncode == 0) == success, (args, result.stdout, result.stderr)
        return result.stdout + result.stderr

    def calls():
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def clear():
        log.write_text("")

    assert "Install from VUP" in run("install", "-n", "demo")
    assert not config.exists()
    assert "Build from source" in run("install", "--build", "-n", "source-only")
    dependency_summary = run("install", "parent", "--build", "--dry-run")
    assert "parent-2.0_1 [explicit]" in dependency_summary, dependency_summary
    assert "child-3.0_1 [dependency]" in dependency_summary, dependency_summary
    assert not any(c[0] in ("git", "sudo", "xbps-src") for c in calls())
    assert "cannot be combined" in run("install", "--build", "--prebuilt", "demo", success=False)
    assert "cannot be combined" in run("install", "--prebuilt", "-by", "demo", success=False)
    config.parent.mkdir(parents=True)
    config.write_text("# preferences\nbuild_local = true # source builds\n")
    assert "Build from source" in run("i", "-n", "demo")
    assert "Install from VUP" in run("install", "--prebuilt", "-n", "demo")
    assert config.read_text().endswith("# source builds\n")
    for invalid in ('build_local = typo', 'build_local = "true"', 'build_local = true trailing',
                    'build_local = true\nbuild_local = false', '[install]\nmode = "local"'):
        config.write_text(invalid)
        assert "Invalid" in run("install", "-n", "demo", success=False)
    config.write_text('build_local = false\n')
    clear()
    run("install", "--build", "-y", "source-only")
    commands = calls()
    assert any(c[:2] == ["git", "clone"] for c in commands), commands
    assert any(c == ["xbps-src", "binary-bootstrap"] for c in commands), commands
    assert any(c == ["xbps-src", "-f", "pkg", "apps/source-only"] for c in commands), commands
    installs = [c for c in commands if c[0] == "sudo"]
    assert len(installs) == 1 and "-y" in installs[0] and installs[0][-1] == "source-only", commands
    assert any(arg.endswith("/binpkgs/apps") for arg in installs[0]), installs
    assert "-i" in installs[0] and "--repository=https://repo-default.voidlinux.org/current" in installs[0], installs
    clear()
    run("install", "--build", "-y", "demo")
    assert not any(c[0] == "git" or c == ["xbps-src", "binary-bootstrap"] for c in calls())
    clear()
    run("install", "--prebuilt", "-y", "demo")
    assert not any(c[0] in ("git", "xbps-src") for c in calls())
    assert any(c[0] == "sudo" for c in calls())

    assert "Build from source" in run("install", "demo", "--local", "-n")
    assert "Install from VUP" in run("install", "demo", "--package", "-n")
    clear()
    env["VURU_TEST_FAIL"] = "xbps-src"
    run("install", "demo", "--build", "-y", success=False)
    assert not any(c[0] == "sudo" for c in calls()), calls()
    del env["VURU_TEST_FAIL"]
    clear()
    assert "cancelled" in run("install", "demo", "--build")
    assert not any(c[0] in ("sudo", "git", "xbps-src") for c in calls()), calls()

    # Updates inherit local mode, pass --dry-run to official XBPS, and route
    # VUP upgrades back through the source-build transaction.
    env["VURU_TEST_UPDATE"] = "1"
    config.write_text('build_local = true\n')
    clear()
    update_output = run("update", "--dry-run")
    assert "Build from source" in update_output and "demo-1.0_1 [explicit]" in update_output, update_output
    assert "source-only-1.0_1 [explicit]" in update_output, update_output
    assert any(c[0] == "sudo" and "-Su" in c and "-n" in c for c in calls()), calls()
    assert not any(c[0] in ("git", "xbps-src") for c in calls()), calls()
    clear()
    run("update", "--build", "--yes")
    update_calls = calls()
    assert any(c == ["xbps-src", "-f", "pkg", "apps/demo"] for c in update_calls), update_calls
    assert any(c == ["xbps-src", "-f", "pkg", "apps/source-only"] for c in update_calls), update_calls
    assert not any("https://example.test/repo" in c for c in update_calls), update_calls
    clear()
    prebuilt_output = run("update", "--prebuilt", "--dry-run")
    assert "Build from source" not in prebuilt_output
    assert "source-only" not in prebuilt_output
    assert any(c[0] == "sudo" and "https://example.test/repo" in c and "-n" in c for c in calls()), calls()
    del env["VURU_TEST_UPDATE"]

    # Exercise the actual first-launch terminal prompt, including both choices.
    config.unlink()
    for answer, expected in ((b"yes\n", "true"), (b"\n", "false")):
        master, slave = pty.openpty()
        proc = subprocess.Popen([binary], env=env, stdin=slave, stdout=slave, stderr=slave)
        os.close(slave)
        output = b""
        deadline = time.monotonic() + 10
        try:
            while b"[y/N]" not in output:
                assert time.monotonic() < deadline, output
                if select.select([master], [], [], 0.1)[0]:
                    output += os.read(master, 4096)
            os.write(master, answer)
            proc.wait(timeout=5)
            while select.select([master], [], [], 0.1)[0]:
                try:
                    output += os.read(master, 4096)
                except OSError:
                    break
            assert config.exists(), output
            assert config.read_text() == f'build_local = {expected}\n'
            assert "Welcome" not in run("help")
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
            os.close(master)
        config.unlink()
    print("Install mode regression tests passed")
