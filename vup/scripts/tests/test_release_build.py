"""Verify release exit status and report preservation using a fake compiler."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[3]
workflow = (ROOT / '.github/workflows/build.yml').read_text()
block = workflow.split('      - name: Prepare Artifacts\n')[1]
PREPARE_SCRIPT = textwrap.dedent(block.split('        run: |\n')[1].split('\n      - name:')[0])


class ReleaseBuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'void-packages/srcpkgs').mkdir(parents=True)
        for name in ['alpha', 'beta']:
            pkg = self.root / 'vup/vup/srcpkgs/core' / name
            pkg.mkdir(parents=True)
            (pkg / 'template').write_text('archs="x86_64 aarch64"\n')
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        compiler = bin_dir / 'vuru'
        compiler.write_text(textwrap.dedent('''\
            #!/bin/sh
            for pkg; do :; done
            echo "Build output for $pkg"
            [ "$pkg" != "$FAIL_PACKAGE" ]
        '''))
        compiler.chmod(0o755)
        self.env = {
            **os.environ, 'PATH': f'{bin_dir}:{os.environ["PATH"]}',
            'CATEGORY': 'core', 'ARCH': 'aarch64', 'PACKAGES': 'alpha beta',
            'FAIL_PACKAGE': '',
        }

    def build(self, **env):
        return subprocess.run(
            [sys.executable, str(ROOT / 'vup/scripts/build_runner.py')],
            cwd=self.root / 'void-packages', env={**self.env, **env},
            capture_output=True, text=True,
        )

    def report(self, category='core'):
        return json.loads((self.root / f'void-packages/report-{category}-aarch64.json').read_text())

    def test_successful_build_exits_zero(self):
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([r['status'] for r in self.report()['results']], ['success', 'success'])

    def test_failed_package_exits_nonzero_and_preserves_remaining_results(self):
        result = self.build(FAIL_PACKAGE='alpha')
        self.assertNotEqual(result.returncode, 0)
        report = self.report()
        self.assertEqual([r['status'] for r in report['results']], ['failure', 'success'])
        self.assertIn('Build output for alpha', report['results'][0]['error_log'])
        self.assertFalse((self.root / 'void-packages/srcpkgs/alpha').exists())

    def test_failed_build_logs_can_still_be_prepared_for_upload(self):
        self.assertNotEqual(self.build(FAIL_PACKAGE='alpha').returncode, 0)
        result = subprocess.run(
            ['bash', '-e', '-c', PREPARE_SCRIPT], cwd=self.root,
            env=self.env, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / 'logs-out/report-core-aarch64.json').exists())
        self.assertIn('Build output for alpha', (self.root / 'logs-out/alpha.log').read_text())

    def test_empty_build_cannot_pass(self):
        self.assertNotEqual(self.build(PACKAGES='deleted').returncode, 0)
        self.assertEqual(self.report()['results'], [])

    def test_unsupported_architecture_cannot_pass_without_building(self):
        for template in self.root.glob('vup/vup/srcpkgs/core/*/template'):
            template.write_text('archs="x86_64"\n')
        self.assertNotEqual(self.build().returncode, 0)
        self.assertEqual(self.report()['results'], [])

    def test_missing_category_still_writes_architecture_report(self):
        self.assertNotEqual(self.build(CATEGORY='missing').returncode, 0)
        self.assertEqual(self.report('missing'), {
            'category': 'missing', 'arch': 'aarch64', 'results': [],
        })


if __name__ == '__main__':
    unittest.main()
