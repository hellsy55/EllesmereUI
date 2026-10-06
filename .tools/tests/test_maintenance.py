"""Deterministic runtime probes and release workflow contracts in disposable Git repos.

Run with the pinned runtime: <python_runtime> -B .tools/tests/test_maintenance.py
No network, external Python packages, addon installation, or project branch writes.
"""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / '.tools' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


runtime = load('python_runtime')
release = load('release_target')
classifier = load('classify_library_range')
libraries = load('check_lib_updates')


class RuntimeTests(unittest.TestCase):
    def runner(self, available, failed_helper=False):
        calls = []
        executable = str(ROOT / 'test Python' / 'python.exe')

        def run(command, **kwargs):
            calls.append(command)
            if '--help' in command:
                self.assertEqual(command[0], executable)
                return subprocess.CompletedProcess(command, int(failed_helper), '', '')
            key = tuple(command[:-2])
            if key not in available:
                raise FileNotFoundError(key)
            version = available[key]
            return subprocess.CompletedProcess(command, 0, json.dumps([executable, version]), '')
        return run, calls, executable

    def test_launchers(self):
        for platform, command in [('win32', ('py', '-3')), ('win32', ('python',)),
                                  ('win32', ('python3',)), ('linux', ('python',)),
                                  ('linux', ('python3',))]:
            with self.subTest(platform=platform, command=command):
                run, calls, executable = self.runner({command: [3, 12, 10]})
                result = runtime.resolve(platform, run, 'missing-bootstrap')
                self.assertEqual(result, {'python': executable, 'version': '3.12.10'})
                self.assertEqual(len([c for c in calls if '--help' in c]), len(runtime.HELPERS))

    def test_python2_candidate_rejected_and_next_used(self):
        run, calls, _ = self.runner({('python3',): [2, 7, 18], ('python',): [3, 12, 10]})
        self.assertEqual(runtime.resolve('linux', run, 'missing')['version'], '3.12.10')

    def test_no_python_or_only_python2(self):
        for available in [{}, {('python',): [2, 7, 18]}]:
            run, calls, _ = self.runner(available)
            with self.assertRaisesRegex(RuntimeError, 'require.*Python 3'):
                runtime.resolve('linux', run, 'missing')
            self.assertFalse(any('--help' in c for c in calls))
            self.assertTrue(all('-c' in c for c in calls))

    def test_python2_bootstrap_rejected(self):
        with patch.object(runtime.sys, 'version_info', (2, 7, 18)):
            with self.assertRaisesRegex(RuntimeError, 'Python 3'):
                runtime.resolve()

    def test_incompatible_helpers_rejected(self):
        run, _, _ = self.runner({('python3',): [3, 6, 0]}, failed_helper=True)
        with self.assertRaises(RuntimeError):
            runtime.resolve('linux', run, 'missing')

    def test_broken_or_timed_out_launcher(self):
        for failure in [OSError('broken'), subprocess.TimeoutExpired('python', 10)]:
            with patch.object(runtime.subprocess, 'run', side_effect=failure):
                with self.assertRaises(RuntimeError):
                    runtime.resolve('linux', current='missing')

    def test_real_runtime_reused_for_all_helpers(self):
        result = runtime.resolve()
        executable = result['python']
        with patch.object(runtime, 'resolve', side_effect=AssertionError('Repeated discovery')):
            for helper in runtime.HELPERS:
                checked = subprocess.run([executable, '-B', str(ROOT / helper), '--help'], capture_output=True)
                self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_preflight_order_and_helper_references(self):
        skill = (ROOT / '.agents/skills/eui-update/SKILL.md').read_text(encoding='utf-8')
        self.assertLess(skill.index('Python preflight'), skill.index('## Sync A'))
        self.assertIn('before any branch changes', skill)
        self.assertNotIn('py -3 .tools/release_target.py', skill)
        self.assertNotIn('py -3 .tools/classify_library_range.py', skill)
        libs = (ROOT / '.agents/skills/eui-libs/SKILL.md').read_text(encoding='utf-8')
        self.assertNotIn('scripts/check_lib_updates.py', libs)
        self.assertIn('Reuse `python_runtime`', libs)


class GitContractTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='eui-maintenance-')
        self.previous = os.getcwd()
        os.chdir(self.temporary.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Maintenance Tests')
        self.git('config', 'user.email', 'maintenance@example.invalid')
        self.git('config', 'commit.gpgsign', 'false')
        self.git('config', 'core.autocrlf', 'false')
        self.commit('initial', 'initial.txt')

    def tearDown(self):
        os.chdir(self.previous)
        self.temporary.cleanup()

    def git(self, *args):
        result = subprocess.run(['git', *args], capture_output=True, encoding='utf-8', errors='replace')
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def ancestor(self, source, target):
        return subprocess.run(['git', 'merge-base', '--is-ancestor', source, target], capture_output=True).returncode == 0

    def commit(self, subject, path, content='fixture\n'):
        target = Path(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding='utf-8')
        self.git('add', '--', path)
        self.git('commit', '-q', '-m', subject)
        return self.git('rev-parse', 'HEAD')

    def test_head_at_release_and_noop(self):
        sha = self.commit('Release v1.0', 'release.txt')
        self.git('branch', 'new-features', sha)
        result = release.resolve_release('HEAD')
        self.assertEqual(result['release_target'], sha)
        self.assertEqual(result['post_release_commits'], 0)
        self.assertTrue(self.ancestor(result['release_target'], 'new-features'))

    def test_post_release_excluded_and_frozen(self):
        base = self.commit('Release v1.0', 'release.txt')
        self.git('branch', 'new-features', base)
        official = self.commit('Release v1.1', 'new-release.txt')
        post = self.commit('later upstream library change', 'Libs/Example/Example.lua')
        self.git('branch', 'upstream-main', post)
        self.git('branch', 'main-mirror', base)
        frozen = release.resolve_release('HEAD')
        self.assertEqual(frozen['release_target'], official)
        self.git('switch', '-q', 'main-mirror')
        self.git('merge', '--ff-only', 'upstream-main')
        self.assertEqual(self.git('rev-parse', 'main-mirror'), post)
        self.assertEqual(frozen['post_release_commits'], 1)
        self.assertEqual(classifier.classify(base, official), {'changes': []})
        self.assertEqual(classifier.classify(official, post)['changes'][0]['library'], 'Libs/Example')
        self.git('switch', '-q', 'new-features')
        self.git('merge', '--ff-only', frozen['release_target'])
        self.assertFalse(self.ancestor(post, 'new-features'))
        self.assertTrue(self.ancestor(official, 'new-features'))
        self.assertEqual(frozen['release_target'], official)

    def test_no_release_does_not_mutate(self):
        Path('body.txt').write_text('body fixture\n', encoding='utf-8')
        self.git('add', 'body.txt')
        self.git('commit', '-q', '-m', 'Fix behavior', '-m', 'Release v1.0')
        before = self.git('show-ref', '--heads')
        self.git('tag', 'Release-v1.0')
        with self.assertRaisesRegex(RuntimeError, 'No release commit'):
            release.resolve_release('HEAD')
        self.assertEqual(before, self.git('show-ref', '--heads'))

    def test_ptr_and_both_propagate_retail_features_without_new_release(self):
        for mode in ['PTR', 'Both']:
            with self.subTest(mode=mode):
                official = self.commit('Release v' + mode, mode + '-release.txt')
                retail = 'retail-' + mode
                ptr = 'ptr-' + mode
                self.git('branch', retail, official)
                self.git('branch', ptr, official)
                post = self.commit('post-release', mode + '-excluded.txt')
                upstream = self.git('rev-parse', 'HEAD')
                self.git('switch', '-q', retail)
                feature = self.commit('fork feature', mode + '-feature.txt')
                frozen = release.resolve_release(upstream)
                self.assertTrue(self.ancestor(frozen['release_target'], retail))
                self.assertFalse(self.ancestor(retail, ptr))
                self.git('switch', '-q', ptr)
                self.git('merge', '--ff-only', retail)
                self.assertTrue(self.ancestor(feature, ptr))
                self.assertFalse(self.ancestor(post, retail))
                self.assertFalse(self.ancestor(post, ptr))

    def test_no_python_preserves_dirty_tree_and_refs(self):
        Path('initial.txt').write_text('user edit\n', encoding='utf-8')
        before = self.git('show-ref', '--heads')
        with patch.object(runtime.subprocess, 'run', side_effect=FileNotFoundError):
            with self.assertRaises(RuntimeError):
                runtime.resolve('linux', current='missing')
        self.assertEqual(before, self.git('show-ref', '--heads'))
        self.assertEqual(Path('initial.txt').read_text(encoding='utf-8'), 'user edit\n')

    def test_metadata_externals_classification(self):
        old = self.commit('old metadata', '.pkgmeta', 'externals:\n  Libs/Example:\n    url: https://example.invalid\n    tag: old\n')
        new = self.commit('new metadata', '.pkgmeta', 'externals:\n  Libs/Example:\n    url: https://example.invalid\n    tag: new\n')
        self.assertEqual(classifier.classify(old, new)['changes'], [{'library': 'Libs/Example', 'status': 'M', 'files': 0}])


class LibraryTests(unittest.TestCase):
    def test_existing_parser_equivalence(self):
        text = (ROOT / '.pkgmeta').read_text(encoding='utf-8')
        parsed = libraries.parse_externals(text)
        self.assertTrue(parsed)
        self.assertTrue(all(value.get('url') for value in parsed.values()))

    def test_compact_healthy_and_unresolved(self):
        for resolved, expected in [(('git-tag', 'v1'), 0), (None, 1)]:
            output = io.StringIO()
            with patch.object(sys, 'argv', ['checker']), patch.object(libraries, 'parse_externals', return_value={'Libs/A': {'url': 'example'}}), patch.object(libraries, 'load_lockfile', return_value={'Libs/A': {'value': 'v1'}}), patch.object(libraries, 'resolve_upstream_version', return_value=resolved), patch.object(libraries, 'relevant_files', return_value={'A.lua': b'payload'}), patch.object(libraries, 'upstream_files', return_value={'A.lua': b'payload'}), patch.object(libraries, 'run', return_value=subprocess.CompletedProcess([], 0, 'retail', '')), contextlib.redirect_stdout(output), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(libraries.main(), expected)
            self.assertIn('Libraries | branch=', output.getvalue())
            self.assertNotIn('[=]', output.getvalue())


class VendoringRegressionTests(unittest.TestCase):
    # Mock external commands in a child process, keeping the real checker,
    # filesystem copies, lockfile I/O, output, and CLI exit behavior.
    HARNESS = r'''
import importlib.util
from pathlib import Path
import subprocess
import sys

checker_path, scenario, selected = sys.argv[1:]
spec = importlib.util.spec_from_file_location('checker', checker_path)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
original_copytree = checker.shutil.copytree

def fake_run(command, **kwargs):
    code, output, error = 0, '', ''
    if command[:2] == ['git', 'rev-parse']:
        output = 'new-features\n'
    elif command[:2] == ['svn', 'info']:
        output = '<info><entry><commit revision="2"/></entry></info>'
    elif command[:2] == ['svn', 'export']:
        assert command[command.index('-r') + 1] == '2'
        if scenario == 'export-failure' or (scenario == 'batch-failure' and 'Second' in command[-2]):
            code, error = 1, 'simulated export failure'
        else:
            Path(command[-1], 'library.lua').write_text('new library\n', encoding='utf-8')
    elif command[:2] == ['git', 'ls-remote']:
        output = 'abcdef\trefs/tags/v2\n' if '--tags' in command else 'c' * 40 + '\tHEAD\n'
    elif command[:2] == ['git', 'clone']:
        if scenario == 'git-clone-failure' or (scenario in ('git-checkout-failure', 'git-fallback-success') and '--depth' in command):
            code, error = 1, 'simulated clone failure'
        else:
            Path(command[-1]).mkdir(parents=True)
            Path(command[-1], 'library.lua').write_text('new library\n', encoding='utf-8')
    elif command[:2] == ['git', 'checkout']:
        if scenario == 'git-checkout-failure':
            code, error = 1, 'simulated checkout failure'
    else:
        raise AssertionError(command)
    return subprocess.CompletedProcess(command, code, output, error)

def copytree(source, destination, **kwargs):
    if scenario == 'copy-failure' and str(destination) == 'Libs/Example':
        raise OSError('simulated vendoring copy failure')
    if scenario == 'cache-failure' and str(destination).startswith('.pkgmeta-cache'):
        raise OSError('simulated cache copy failure')
    return original_copytree(source, destination, **kwargs)

def replace_failure(*args):
    raise PermissionError('simulated lockfile publication failure')

checker.run = fake_run
# Synthetic version IDs exercise vendoring I/O; advance proof has separate tests.
checker.require_version_advance = lambda *args: None
checker.shutil.copytree = copytree
if scenario == 'lockfile-failure':
    checker.os.replace = replace_failure
# Vendoring tests operate only on disposable fixtures. Do not execute an apply CLI.
sys.argv = [checker_path]
checker.argparse.ArgumentParser.parse_args = lambda self: checker.argparse.Namespace(apply=selected)
sys.exit(checker.main())
'''

    def invoke(self, scenario):
        with tempfile.TemporaryDirectory(prefix='eui-vendoring-') as temporary:
            root = Path(temporary)
            git_source = scenario.startswith('git-')
            commit_source = scenario == 'git-commit-success'
            names = ['Example', 'Second'] if scenario == 'batch-failure' else ['Example']
            metadata = 'externals:\n'
            old = {}
            for name in names:
                url = 'https://example.invalid/library.git' if git_source else 'https://repos.wowace.com/' + name
                metadata += f'  Libs/{name}:\n    url: {url}\n'
                if git_source and not commit_source:
                    metadata += '    tag: latest\n'
                old['Libs/' + name] = {'kind': 'git-commit' if commit_source else 'git-tag' if git_source else 'svn-rev', 'value': '1'}
                target = root / 'Libs' / name
                target.mkdir(parents=True)
                (target / 'old.lua').write_text('previous library\n', encoding='utf-8')
            (root / '.pkgmeta').write_text(metadata, encoding='utf-8')
            previous = (json.dumps(old, indent=4) + '\n').encode('utf-8')
            lock = root / '.pkgmeta-lock.json'
            lock.write_bytes(previous)
            result = subprocess.run([sys.executable, '-B', '-c', self.HARNESS,
                                     str(ROOT / '.tools/check_lib_updates.py'), scenario,
                                     'all' if len(names) > 1 else 'Example'],
                                    cwd=root, capture_output=True, encoding='utf-8')
            return result, previous, lock.read_bytes(), sorted(p.name for p in root.iterdir()), (root / 'Libs/Example/library.lua').exists()

    def test_vendoring_failures_preserve_lock_and_report_failure(self):
        for scenario in ['export-failure', 'git-clone-failure', 'git-checkout-failure',
                         'copy-failure', 'cache-failure', 'batch-failure', 'lockfile-failure']:
            with self.subTest(scenario=scenario):
                result, previous, actual, files, _ = self.invoke(scenario)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(actual, previous)
                self.assertIn('[error]', result.stderr)
                self.assertNotIn('updated to', result.stdout)
                self.assertNotIn('.pkgmeta-lock.json updated', result.stdout)
                self.assertLessEqual(set(files), {'.pkgmeta', '.pkgmeta-cache', '.pkgmeta-lock.json', 'Libs'})
                self.assertFalse(any(name.startswith('tmp') for name in files))

    def test_successful_vendoring_publishes_version_and_reports_success(self):
        for scenario, expected in [('export-success', '2'), ('git-success', 'v2'), ('git-fallback-success', 'v2'),
                                   ('git-commit-success', 'c' * 40)]:
            with self.subTest(scenario=scenario):
                result, _, actual, _, installed = self.invoke(scenario)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(installed)
                self.assertEqual(json.loads(actual)['Libs/Example']['value'], expected)
                self.assertIn('Example updated to ' + expected, result.stdout)
                self.assertIn('.pkgmeta-lock.json updated', result.stdout)
                self.assertEqual(result.stderr, '')


if __name__ == '__main__':
    unittest.main(verbosity=1)
