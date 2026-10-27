"""Validation workflow contracts and real event-script execution in temporary Git repos."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
BASH = 'C:/Program Files/Git/bin/bash.exe' if os.name == 'nt' else shutil.which('bash')
GUARD = (ROOT / '.github/workflows/guardrails.yml').read_text(encoding='utf-8')
LOCALE = (ROOT / '.github/workflows/locale-check.yml').read_text(encoding='utf-8')


def event_script():
    block = GUARD.split('      - name: Run guardrails\n', 1)[1].split('        run: |\n', 1)[1]
    return '\n'.join(line[10:] for line in block.splitlines()) + '\n'


class Contracts(unittest.TestCase):
    def test_branch_and_security_contracts(self):
        for source in (GUARD, LOCALE):
            self.assertIn('branches: [main, new-features, 12.1.7-PTR-features]', source)
            self.assertIn('permissions:\n  contents: read', source)
            self.assertIn('persist-credentials: false', source)
            self.assertNotIn('pull_request_target:', source)
            self.assertNotIn('workflow_dispatch:', source)
        push = GUARD.split('  push:\n', 1)[1].split('\npermissions:', 1)[0]
        self.assertNotIn('paths:', push)

    def test_lua_toc_and_test_paths(self):
        self.assertIn("'**.[lL][uU][aA]'", GUARD)
        self.assertIn("'**.[tT][oO][cC]'", GUARD)
        self.assertIn("'**/*.lua'", LOCALE)
        for name in ['.tools/tests/test_locale_keys.py', '.tools/tests/test_validation_workflows.py',
                     '.github/workflows/locale-check.yml']:
            self.assertEqual(LOCALE.count("- '" + name + "'"), 2)
        self.assertIn('.tools/tests/test_validation_workflows.py', GUARD)
        self.assertIn('python3 -B .tools/tests/test_validation_workflows.py', GUARD)
        self.assertIn('python3 -B .tools/tests/test_locale_keys.py', LOCALE)
        self.assertIn('bash .tools/extract-locale-keys.sh --check', LOCALE)

    def test_immutable_event_revisions(self):
        self.assertIn('${{ github.event.pull_request.base.sha || github.event.before }}', GUARD)
        self.assertIn('EXPECTED_HEAD: ${{ github.sha }}', GUARD)
        self.assertIn('fetch-depth: 0', GUARD)
        self.assertNotIn('HEAD~1', GUARD)
        self.assertNotIn('origin/${', GUARD)
        self.assertNotIn('format(', GUARD)
        self.assertIn('--base "$BASE" --head "$actual_head"', GUARD)


@unittest.skipUnless(BASH and Path(BASH).is_file(), 'Bash is required')
class EventExecution(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='eui-events-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git = shutil.which('git')
        self.assertIsNotNone(self.git)
        self.command('init', '-q')
        self.command('config', 'user.name', 'Validation Fixture')
        self.command('config', 'user.email', 'fixture@example.invalid')
        self.command('config', 'commit.gpgSign', 'false')
        self.command('config', 'core.hooksPath', 'no-hooks')
        tools = self.root / '.tools'
        tools.mkdir()
        for name in ('guardrails.py', 'lua_runtime.py'):
            shutil.copyfile(ROOT / '.tools' / name, tools / name)
        (self.root / 'event.sh').write_text(event_script(), encoding='utf-8', newline='\n')
        # Use the exact frozen test interpreter on Windows as well as Linux.
        (self.root / 'python3').write_text('#!/usr/bin/env bash\nexec "' +
                                         Path(sys.executable).as_posix() + '" "$@"\n',
                                         encoding='utf-8', newline='\n')
        (self.root / 'python3').chmod(0o755)
        self.base = self.commit()

    def command(self, *args):
        return subprocess.run([self.git, *args], cwd=self.root, capture_output=True,
                              text=True, check=True).stdout.strip()

    def commit(self):
        self.command('add', '-A')
        self.command('commit', '-qm', 'Validation (test): create fixture', '--allow-empty')
        return self.command('rev-parse', 'HEAD')

    def run_event(self, base, head=None, forced='false', event='push'):
        env = dict(os.environ, BASE=base, EXPECTED_HEAD=head or self.command('rev-parse', 'HEAD'),
                   EVENT_NAME=event, FORCED=forced, PYTHONDONTWRITEBYTECODE='1')
        return subprocess.run([BASH, '-c', 'export PATH="$PWD:$PATH"; bash event.sh'],
                              cwd=self.root, env=env, capture_output=True, text=True)

    def test_script_syntax(self):
        result = subprocess.run([BASH, '-n', 'event.sh'], cwd=self.root, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_normal_push_one_and_multiple_commits(self):
        for count in (1, 3):
            with self.subTest(count=count):
                for i in range(count):
                    (self.root / 'notes.txt').write_text(str(i), encoding='utf-8')
                    head = self.commit()
                result = self.run_event(self.base, head)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('merge-base=' + self.base, result.stdout)
                self.assertIn('Checked out revision: ' + head, result.stdout)

    def test_initial_missing_invalid_and_wrong_checkout_fail(self):
        for base, head in [('', None), ('0' * 40, None), ('f' * 40, None),
                           ('missing-base', None), (self.base, 'f' * 40)]:
            with self.subTest(base=base, head=head):
                result = self.run_event(base, head)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertIn('::error::', result.stdout)
                self.assertNotIn('guardrails OK', result.stdout)

    def test_force_push_related_and_unrelated(self):
        (self.root / 'old.txt').write_text('old', encoding='utf-8')
        previous = self.commit()
        self.command('checkout', '-qb', 'rewritten', self.base)
        (self.root / 'new.txt').write_text('new', encoding='utf-8')
        self.commit()
        result = self.run_event(previous, forced='true')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('forced: true', result.stdout)
        self.assertIn('merge-base=' + self.base, result.stdout)
        self.command('checkout', '--orphan', 'unrelated')
        # Preserve the fixture tools while replacing its ancestry.
        self.commit()
        result = self.run_event(previous, forced='true')
        self.assertEqual(result.returncode, 2)
        self.assertIn('no common ancestor', result.stderr)

    def test_pr_records_event_merge_revision(self):
        head = self.commit()
        result = self.run_event(self.base, head, event='pull_request', forced='')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Expected revision: ' + head, result.stdout)


if __name__ == '__main__':
    unittest.main()
