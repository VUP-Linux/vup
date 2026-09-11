"""Exercise the actual PR build shell with a fake compiler; no Docker required."""
import importlib.util
import contextlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / '.github/workflows/pr-check.yml'
block = WORKFLOW.read_text().split('      - name: Build Modified Packages\n')[1]
BUILD_SCRIPT = textwrap.dedent(block.split('        run: |\n')[1].split('\n      - name:')[0])
sys.path.insert(0, str(ROOT / 'vup/scripts'))
spec = importlib.util.spec_from_file_location('check_changes', ROOT / 'vup/scripts/check_changes.py')
check_changes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_changes)


class BuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'void-packages/srcpkgs').mkdir(parents=True)
        scripts = self.root / 'vup/vup/scripts'
        scripts.mkdir(parents=True)
        shutil.copy(ROOT / 'vup/scripts/update_report.py', scripts)
        self.packages = self.root / 'vup/vup/srcpkgs/core'
        for name in ['alpha', 'beta']:
            (self.packages / name).mkdir(parents=True)
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        compiler = bin_dir / 'vuru'
        compiler.write_text(textwrap.dedent('''\
            #!/bin/sh
            echo "$*" >> "$COMMANDS"
            for pkg; do :; done
            if [ "$pkg" = binary-bootstrap ]; then
                [ "$FAIL_BOOTSTRAP" != yes ]
                exit $?
            fi
            echo "$pkg" >> "$CALLS"
            echo "Compiled $pkg"
            [ "$pkg" != "$FAIL_PACKAGE" ]
        '''))
        compiler.chmod(0o755)
        shutil.copy(compiler, self.root / 'void-packages/xbps-src')
        self.env = {
            **os.environ, 'PATH': f'{bin_dir}:{os.environ["PATH"]}',
            'CATEGORY': 'core', 'ARCH': 'x86_64', 'PACKAGES': 'alpha beta',
            'FAIL_PACKAGE': '', 'FAIL_BOOTSTRAP': '',
            'CALLS': str(self.root / 'calls'),
            'COMMANDS': str(self.root / 'commands'),
        }

    def build(self, **env):
        return subprocess.run(
            ['bash', '--noprofile', '--norc', '-e', '-o', 'pipefail', '-c', BUILD_SCRIPT],
            cwd=self.root, env={**self.env, **env}, capture_output=True, text=True,
        )

    def test_success_builds_all_selected_packages(self):
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'calls').read_text().splitlines(), ['alpha', 'beta'])
        report = json.loads((self.root / 'reports/report-core-x86_64.json').read_text())
        self.assertEqual([entry['status'] for entry in report], ['success', 'success'])

    def test_failure_is_nonzero_but_remaining_packages_still_build(self):
        result = self.build(FAIL_PACKAGE='alpha')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.root / 'calls').read_text().splitlines(), ['alpha', 'beta'])
        report = json.loads((self.root / 'reports/report-core-x86_64.json').read_text())
        self.assertEqual([entry['status'] for entry in report], ['failure', 'success'])

    def test_all_packages(self):
        self.assertEqual(self.build(PACKAGES='ALL').returncode, 0)

    def test_cross_architecture_is_passed_to_compiler_and_reports_do_not_collide(self):
        for arch in ['x86_64', 'aarch64', 'armv7l', 'aarch64-musl']:
            with self.subTest(arch=arch):
                result = self.build(ARCH=arch, PACKAGES='alpha')
                self.assertEqual(result.returncode, 0, result.stderr)
                report = json.loads((self.root / f'reports/report-core-{arch}.json').read_text())
                self.assertEqual(report[0]['status'], 'success')
        self.assertEqual((self.root / 'commands').read_text().splitlines(), [
            'src pkg alpha', 'src -a aarch64 pkg alpha',
            'src -a armv7l pkg alpha', 'src -a aarch64-musl pkg alpha',
        ])

    def test_same_cpu_musl_uses_separate_native_root(self):
        result = self.build(ARCH='x86_64-musl', PACKAGES='alpha')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'commands').read_text().splitlines(), [
            '-A x86_64-musl binary-bootstrap', '-A x86_64-musl pkg alpha',
        ])

    def test_failed_musl_bootstrap_cannot_pass(self):
        self.assertNotEqual(self.build(ARCH='x86_64-musl', FAIL_BOOTSTRAP='yes').returncode, 0)
        self.assertFalse((self.root / 'calls').exists())

    def test_arm_failure_fails_even_when_x86_succeeds(self):
        self.assertEqual(self.build(PACKAGES='alpha').returncode, 0)
        self.assertNotEqual(self.build(ARCH='aarch64', FAIL_PACKAGE='alpha').returncode, 0)
        report = json.loads((self.root / 'reports/report-core-aarch64.json').read_text())
        self.assertEqual([entry['status'] for entry in report], ['failure', 'success'])

    def test_missing_packages_cannot_pass(self):
        self.assertNotEqual(self.build(PACKAGES='deleted').returncode, 0)

    def test_empty_category_cannot_pass(self):
        self.assertNotEqual(self.build(CATEGORY='missing', PACKAGES='ALL').returncode, 0)

    def test_package_and_category_are_data_not_shell_code(self):
        for field in ['CATEGORY', 'PACKAGES', 'ARCH']:
            with self.subTest(field=field):
                self.assertNotEqual(self.build(**{field: '$(touch injected)'}).returncode, 0)
                self.assertFalse((self.root / 'void-packages/injected').exists())

    def test_path_traversal_is_rejected(self):
        for field in ['CATEGORY', 'PACKAGES', 'ARCH']:
            with self.subTest(field=field):
                self.assertNotEqual(self.build(**{field: '../outside'}).returncode, 0)


class ChangeSelectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name, archs in {
            'x86': 'x86_64', 'both': 'x86_64 aarch64', 'arm': 'aarch64',
            'musl': 'x86_64-musl aarch64-musl',
        }.items():
            package = self.root / 'vup/srcpkgs/core' / name
            package.mkdir(parents=True)
            (package / 'template').write_text(f'archs="{archs}"\n')

    def matrix(self, event, changes):
        output = self.root / 'output'
        with contextlib.chdir(self.root), contextlib.redirect_stdout(io.StringIO()), \
             patch.dict(os.environ, {'GITHUB_EVENT_NAME': event, 'GITHUB_OUTPUT': str(output)}), \
             patch.object(check_changes, 'get_changes', return_value=changes):
            check_changes.main()
        values = dict(line.split('=', 1) for line in output.read_text().splitlines())
        return values['should_run'], json.loads(values['matrix'])['include']

    def test_pr_and_release_cover_all_declared_architectures(self):
        changes = ['vup/srcpkgs/core/both/template']
        expected = ('true', [
            {'category': 'core', 'arch': 'aarch64', 'packages': 'both'},
            {'category': 'core', 'arch': 'x86_64', 'packages': 'both'},
        ])
        self.assertEqual(self.matrix('pull_request', changes), expected)
        self.assertEqual(self.matrix('push', changes), expected)

    def test_mixed_category_only_builds_compatible_packages(self):
        _, matrix = self.matrix('pull_request', [
            'vup/srcpkgs/core/x86/template', 'vup/srcpkgs/core/both/template',
        ])
        self.assertEqual({row['arch']: row['packages'] for row in matrix}, {
            'x86_64': 'both x86', 'aarch64': 'both',
        })

    def test_arm_only_pr_is_not_skipped(self):
        self.assertEqual(self.matrix('pull_request', ['vup/srcpkgs/core/arm/template']), (
            'true', [{'category': 'core', 'arch': 'aarch64', 'packages': 'arm'}],
        ))

    def test_full_build_includes_musl_and_filters_each_target(self):
        _, matrix = self.matrix('pull_request', 'ALL')
        self.assertEqual({row['arch']: row['packages'] for row in matrix}, {
            'x86_64': 'both x86', 'aarch64': 'arm both',
            'x86_64-musl': 'musl', 'aarch64-musl': 'musl',
        })

    def test_deleted_package_does_not_schedule_an_empty_job(self):
        self.assertEqual(self.matrix('push', ['vup/srcpkgs/core/deleted/template']), ('false', []))

    def test_pr_uses_captured_base_and_preserves_filename_boundaries(self):
        sha = 'a' * 40
        with patch.dict(os.environ, {'GITHUB_EVENT_NAME': 'pull_request', 'PR_BASE_SHA': sha}), \
             patch.object(check_changes.subprocess, 'check_call') as fetch, \
             patch.object(check_changes.subprocess, 'check_output', return_value=b'file\nname\0other\0') as diff:
            self.assertEqual(check_changes.get_changes(), ['file\nname', 'other'])
            fetch.assert_not_called()
            self.assertIn(f'{sha}...HEAD', diff.call_args.args[0])


if __name__ == '__main__':
    unittest.main()
