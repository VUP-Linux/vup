"""Exercise the actual PR build shell with a fake compiler; no Docker required."""
import importlib.util
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
        compiler.write_text('#!/bin/sh\necho "$3" >> "$CALLS"\n[ "$3" != "$FAIL_PACKAGE" ]\n')
        compiler.chmod(0o755)
        self.env = {
            **os.environ, 'PATH': f'{bin_dir}:{os.environ["PATH"]}',
            'CATEGORY': 'core', 'PACKAGES': 'alpha beta', 'FAIL_PACKAGE': '',
            'CALLS': str(self.root / 'calls'),
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
        report = json.loads((self.root / 'reports/report-core.json').read_text())
        self.assertEqual([entry['status'] for entry in report], ['success', 'success'])

    def test_failure_is_nonzero_but_remaining_packages_still_build(self):
        result = self.build(FAIL_PACKAGE='alpha')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.root / 'calls').read_text().splitlines(), ['alpha', 'beta'])
        report = json.loads((self.root / 'reports/report-core.json').read_text())
        self.assertEqual([entry['status'] for entry in report], ['failure', 'success'])

    def test_all_packages(self):
        self.assertEqual(self.build(PACKAGES='ALL').returncode, 0)

    def test_missing_packages_cannot_pass(self):
        self.assertNotEqual(self.build(PACKAGES='deleted').returncode, 0)

    def test_empty_category_cannot_pass(self):
        self.assertNotEqual(self.build(CATEGORY='missing', PACKAGES='ALL').returncode, 0)

    def test_package_and_category_are_data_not_shell_code(self):
        for field in ['CATEGORY', 'PACKAGES']:
            with self.subTest(field=field):
                self.assertNotEqual(self.build(**{field: '$(touch injected)'}).returncode, 0)
                self.assertFalse((self.root / 'void-packages/injected').exists())

    def test_path_traversal_is_rejected(self):
        for field in ['CATEGORY', 'PACKAGES']:
            with self.subTest(field=field):
                self.assertNotEqual(self.build(**{field: '../outside'}).returncode, 0)


class ChangeSelectionTests(unittest.TestCase):
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
