"""Report-only library and rootless SVN regressions; no external network."""
import contextlib
import importlib.util
import io
import json
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


checker = load('check_lib_updates')
bootstrap = load('bootstrap_cloud_svn')


class CheckerTests(unittest.TestCase):
    def report(self, upstream, baseline=None, failure=None):
        output = io.StringIO()
        with patch.object(sys, 'argv', ['checker']), patch.object(checker, 'parse_externals', return_value={'Libs/A': {'url': 'example'}}), patch.object(checker, 'load_lockfile', return_value={}), patch.object(checker, 'resolve_upstream_version', return_value=upstream, side_effect=failure), patch.object(checker, 'baseline_without_lock', return_value=baseline), patch.object(checker, 'run', return_value=subprocess.CompletedProcess([], 0, 'work', '')), contextlib.redirect_stdout(output), contextlib.redirect_stderr(io.StringIO()):
            code = checker.main()
        return code, output.getvalue()

    def test_no_lock_equal_is_current(self):
        code, output = self.report(('git-tag', '1.0.2-release'), ('1.0.2-release', '1.0.2-release'))
        self.assertEqual(code, 0)
        self.assertIn('pending=0', output)
        self.assertIn('CHECKED=1', output)
        self.assertIn('UNKNOWN=0', output)

    def test_no_lock_real_advance_is_pending(self):
        code, output = self.report(('git-tag', 'v2'), ('v1', 'v2'))
        self.assertEqual(code, 1)
        self.assertIn('pending=1', output)

    def test_failed_lookup_stays_unknown(self):
        for failure in [None, FileNotFoundError('svn'), RuntimeError('network denied'), subprocess.TimeoutExpired('svn', 60)]:
            with self.subTest(failure=failure):
                code, output = self.report(None, failure=failure)
                self.assertEqual(code, 1)
                self.assertIn('UNKNOWN=1', output)
                self.assertIn('pending=0', output)

    def test_annotated_declared_tag_uses_peeled_commit(self):
        response = subprocess.CompletedProcess([], 0, 'tagobject\trefs/tags/v1.1.4\ncommit\trefs/tags/v1.1.4^{}\n', '')
        with patch.object(checker, 'run', return_value=response):
            self.assertEqual(checker.declared_git_commit('repo', 'v1.1.4'), 'commit')

    def test_pin_compared_to_head_without_lock(self):
        for head, expected in [('commit', ('commit', 'commit')), ('new', ('commit', 'new'))]:
            with patch.object(checker, 'require_version_advance'), patch.object(checker, 'declared_git_commit', return_value='commit'), patch.object(checker, 'relevant_files', return_value={'A.lua': b'same'}), patch.object(checker, 'upstream_files', return_value={'A.lua': b'same'}):
                self.assertEqual(checker.baseline_without_lock('Libs/A', {'url': 'repo', 'tag': 'v1.1.4'}, ('git-commit', head)), expected)

    def test_failed_pin_lookup_is_not_success(self):
        with patch.object(checker, 'declared_git_commit', return_value=None):
            with self.assertRaises(RuntimeError):
                checker.baseline_without_lock('Libs/A', {'url': 'repo', 'tag': 'v1'}, ('git-commit', 'new'))

    def content_report(self, local, remote, failure=None, entry=None):
        output = io.StringIO()
        entry = entry or {'url': 'https://example.invalid/A.git'}
        with patch.object(sys, 'argv', ['checker']), patch.object(checker, 'parse_externals', return_value={'Libs/A': entry}), patch.object(checker, 'load_lockfile', return_value={}), patch.object(checker, 'resolve_upstream_version', return_value=('git-commit', 'c' * 40)), patch.object(checker, 'relevant_files', return_value=local), patch.object(checker, 'upstream_files', return_value=remote, side_effect=failure), patch.object(checker, 'run', return_value=subprocess.CompletedProcess([], 0, 'work', '')), contextlib.redirect_stdout(output), contextlib.redirect_stderr(io.StringIO()):
            code = checker.main()
        return code, output.getvalue()

    def test_same_minor_different_content_is_drift(self):
        local = {'A.lua': b'LibStub:NewLibrary("A", 8)\nold code'}
        remote = {'A.lua': b'LibStub:NewLibrary("A", 8)\nnew code'}
        code, output = self.content_report(local, remote)
        self.assertEqual(code, 1)
        self.assertIn('current=0 | accepted-drift=0 | pending=0 | DRIFT=1 | UNKNOWN=0', output)

    def test_identical_content_without_lock_is_current(self):
        files = {'A.lua': b'LibStub:NewLibrary("A", 8)', 'load.xml': b'<Ui/>'}
        code, output = self.content_report(files, dict(files))
        self.assertEqual(code, 0)
        self.assertIn('current=1 | accepted-drift=0 | pending=0 | DRIFT=0 | UNKNOWN=0', output)

    def test_inconclusive_content_comparison_is_unknown(self):
        for failure in [RuntimeError('comparison unavailable'), subprocess.TimeoutExpired('git', 60)]:
            code, output = self.content_report({}, {}, failure=failure)
            self.assertEqual(code, 1)
            self.assertIn('current=0 | accepted-drift=0 | pending=0 | DRIFT=0 | UNKNOWN=1', output)

    def test_exact_declared_pin_requires_payload_equivalence(self):
        with patch.object(checker, 'declared_git_commit', return_value='c' * 40):
            code, output = self.content_report({'A.lua': b'same'}, {'A.lua': b'same'}, entry={'url': 'repo', 'tag': 'v1.1.4'})
        self.assertEqual(code, 0)
        self.assertIn('current=1 | accepted-drift=0 | pending=0 | DRIFT=0 | UNKNOWN=0', output)

    def test_missing_runtime_file_or_changed_manifest_is_not_current(self):
        local = {'A.lua': b'LibStub:NewLibrary("A", 8)', 'load.xml': b'<Ui/>'}
        for remote in [{'A.lua': local['A.lua']}, dict(local, **{'load.xml': b'<Ui changed/>'}), dict(local, **{'extra.lua': b'extra'})]:
            code, output = self.content_report(local, remote)
            self.assertEqual(code, 1)
            self.assertIn('current=0 | accepted-drift=0 | pending=0 | DRIFT=1 | UNKNOWN=0', output)

    def test_proven_minor_advance_is_pending(self):
        code, output = self.content_report({'A.lua': b'LibStub:NewLibrary("A", 8)'}, {'A.lua': b'LibStub:NewLibrary("A", 9)'})
        self.assertEqual(code, 1)
        self.assertIn('current=0 | accepted-drift=0 | pending=1 | DRIFT=0 | UNKNOWN=0', output)

    def test_older_minor_is_drift(self):
        code, output = self.content_report({'A.lua': b'LibStub:NewLibrary("A", 8)'}, {'A.lua': b'LibStub:NewLibrary("A", 7)'})
        self.assertEqual(code, 1)
        self.assertIn('current=0 | accepted-drift=0 | pending=0 | DRIFT=1 | UNKNOWN=0', output)

    def test_equal_release_marker_does_not_prove_content_equivalence(self):
        code, output = self.content_report({'A.lua': b'local _VERSION = "1.0.2-release"\nold'}, {'A.lua': b'local _VERSION = "1.0.2-release"\nnew'})
        self.assertEqual(code, 1)
        self.assertIn('current=0 | accepted-drift=0 | pending=0 | DRIFT=1 | UNKNOWN=0', output)

    def test_proven_release_advance_is_pending(self):
        code, output = self.content_report({'A.lua': b'local _VERSION = "1.0.2-release"'}, {'A.lua': b'local _VERSION = "1.0.3-release"'})
        self.assertEqual(code, 1)
        self.assertIn('current=0 | accepted-drift=0 | pending=1 | DRIFT=0 | UNKNOWN=0', output)

    def test_moving_alias_is_not_a_declared_pin(self):
        for alias in ['latest', 'Alpha', 'Beta', 'HEAD']:
            with patch.object(checker, 'declared_git_commit', side_effect=AssertionError('Moving alias')):
                code, output = self.content_report({}, {}, failure=RuntimeError('No content proof'), entry={'url': 'repo', 'tag': alias})
            self.assertEqual(code, 1)
            self.assertIn('UNKNOWN=1', output)

    def test_relevant_files_include_all_runtime_sources_and_manifests(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ['A.lua', 'load.xml', 'A.toc', 'README.md']:
                (root / name).write_bytes(name.encode())
            self.assertEqual(set(checker.relevant_files(root)), {'A.lua', 'load.xml', 'A.toc'})
            (root / 'link.lua').symlink_to(root / 'A.lua')
            with self.assertRaisesRegex(RuntimeError, 'symbolic'):
                checker.relevant_files(root)

    def test_git_snapshot_reads_exact_commit_and_subdirectory(self):
        commands = []

        def run(command, **kwargs):
            commands.append(command)
            tree = '100644 blob ' + 'b' * 40 + '\tA/A.lua\0' if 'ls-tree' in command else ''
            return subprocess.CompletedProcess(command, 0, tree, '')

        with patch.object(checker, 'run', side_effect=run), patch.object(checker.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, b'content\r\n', b'')):
            self.assertEqual(checker.upstream_files({'url': 'repo.git/A'}, ('git-commit', 'c' * 40)), {'A.lua': b'content\r\n'})
        self.assertTrue(any(command[-1] == 'c' * 40 and 'fetch' in command for command in commands))

    def test_snapshot_lookup_failure_is_not_equivalence(self):
        with patch.object(checker, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'denied')):
            with self.assertRaisesRegex(RuntimeError, 'denied'):
                checker.upstream_files({'url': 'repo'}, ('git-commit', 'c' * 40))

    def test_parser_stops_at_top_level_scalar(self):
        parsed = checker.parse_externals('externals:\n  Libs/A:\n    url: repo\nenable-nolib-creation: no\nignore:\n  - file\n')
        self.assertEqual(parsed, {'Libs/A': {'url': 'repo'}})

    def test_git_lookup_errors_are_visible(self):
        with patch.object(checker, 'run', return_value=subprocess.CompletedProcess([], 128, '', 'network denied')):
            for lookup in [checker.latest_git_tag, checker.latest_git_commit, lambda url: checker.declared_git_commit(url, 'v1')]:
                with self.assertRaisesRegex(RuntimeError, 'network denied'):
                    lookup('repo')

    def test_real_eui_tag_family_preserves_git_numeric_order(self):
        # Actual LibDeflate tags: no moving aliases or incompatible tag families.
        response = subprocess.CompletedProcess([], 0, 'a\trefs/tags/1.0.2-release^{}\nb\trefs/tags/1.0.2-release\nc\trefs/tags/1.0.1-release\nd\trefs/tags/0.9.0-beta4\n', '')
        with patch.object(checker, 'run', return_value=response) as run:
            self.assertEqual(checker.latest_git_tag('repo'), '1.0.2-release')
            self.assertIn('--sort=-v:refname', run.call_args.args[0])


class ExternalPackagingTests(unittest.TestCase):
    def test_locked_advance_requires_monotonic_revision_or_tag(self):
        for kind, old, new in [('svn-rev', '10', '11'), ('git-tag', 'v1', 'v2'), ('git-tag', '1.0.2-release', '1.0.3-release')]:
            checker.require_version_advance(kind, old, new, {})
            with self.assertRaises(RuntimeError):
                checker.require_version_advance(kind, new, old, {})
        with self.assertRaises(RuntimeError):
            checker.require_version_advance('git-tag', 'alpha', 'beta', {})

    def test_different_git_commits_require_proven_ancestry(self):
        for code in [0, 1, 128]:
            def run(command, **kwargs):
                return subprocess.CompletedProcess(command, code if 'merge-base' in command else 0, '', 'failure')
            with patch.object(checker, 'run', side_effect=run):
                if code == 0:
                    checker.require_version_advance('git-commit', 'a' * 40, 'b' * 40, {'url': 'repo'})
                else:
                    with self.assertRaises(RuntimeError):
                        checker.require_version_advance('git-commit', 'a' * 40, 'b' * 40, {'url': 'repo'})

    def test_svn_trunk_without_tag(self):
        entry = {'url': 'https://repos.wowace.com/wow/A/trunk'}
        with patch.object(checker, 'latest_svn_revision', return_value='42') as lookup:
            self.assertEqual(checker.resolve_upstream_version(entry), ('svn-rev', '42'))
        lookup.assert_called_once_with(entry['url'])

    def test_svn_explicit_tag_and_subdirectory(self):
        for suffix in ['', '/A']:
            entry = {'url': 'https://repos.wowace.com/wow/A/trunk' + suffix, 'tag': '1.0'}
            expected = 'https://repos.wowace.com/wow/A/tags/1.0' + suffix
            with patch.object(checker, 'latest_svn_revision', return_value='20') as lookup:
                self.assertEqual(checker.resolve_upstream_version(entry), ('svn-rev', '20'))
            lookup.assert_called_once_with(expected)
            self.assertEqual(entry['_snapshot_url'], expected)

    def test_failed_svn_tag_is_unknown_without_trunk_fallback(self):
        for result in [None, RuntimeError('SVN tag lookup failed: not found')]:
            entry = {'url': 'https://repos.wowace.com/wow/A/trunk', 'tag': 'missing'}
            output = io.StringIO()
            with patch.object(sys, 'argv', ['checker']), patch.object(checker, 'parse_externals', return_value={'Libs/A': entry}), patch.object(checker, 'load_lockfile', return_value={}), patch.object(checker, 'run', return_value=subprocess.CompletedProcess([], 0, 'work', '')), patch.object(checker, 'latest_svn_revision', return_value=result if result is None else None, side_effect=result if isinstance(result, Exception) else None) as lookup, contextlib.redirect_stdout(output), contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(checker.main(), 1)
            lookup.assert_called_once_with('https://repos.wowace.com/wow/A/tags/missing')
            self.assertIn('DRIFT=0 | UNKNOWN=1', output.getvalue())

    def test_svn_latest_uses_latest_log_addition_not_numeric_sort(self):
        xml = '<log><logentry><paths><path action="M">/tags/old</path><path action="A">/tags/v2/A</path><path action="A">/tags/v99</path></paths></logentry></log>'
        with patch.object(checker, 'run', return_value=subprocess.CompletedProcess([], 0, xml, '')) as run:
            self.assertEqual(checker.svn_external_url({'url': 'repo/trunk/A', 'tag': 'latest'}), 'repo/tags/v2/A')
        self.assertEqual(run.call_args.args[0], ['svn', 'log', '--xml', '--verbose', '--limit', '1', 'repo/tags'])

    def test_svn_latest_missing_or_network_error_fails_closed(self):
        for code, xml in [(0, '<log/>'), (1, '')]:
            with patch.object(checker, 'run', return_value=subprocess.CompletedProcess([], code, xml, 'denied')):
                with self.assertRaises(RuntimeError):
                    checker.svn_external_url({'url': 'repo/trunk', 'tag': 'latest'})

    def test_svn_export_uses_resolved_tag_snapshot_and_metadata(self):
        def export(command, **kwargs):
            self.assertEqual(command[2:5], ['-r', '20', 'repo/tags/1.0/A'])
            root = Path(command[-1])
            root.mkdir()
            (root / 'A.lua').write_bytes(b'runtime')
            (root / 'tests').mkdir()
            (root / 'tests/test.lua').write_bytes(b'test')
            (root / '.pkgmeta').write_text('ignore:\n  - tests\n')
            return subprocess.CompletedProcess(command, 0, '', '')
        with patch.object(checker, 'run', side_effect=export):
            files = checker.upstream_files({'url': 'repo/trunk/A', '_snapshot_url': 'repo/tags/1.0/A'}, ('svn-rev', '20'))
        self.assertEqual(files, {'A.lua': b'runtime'})

    def test_libdeflate_git_metadata_excludes_tests_and_is_current(self):
        runtime = b'local _VERSION = "1.0.2-release"'
        blobs = {'a': runtime, 'b': b'test', 'c': b'ignore:\n  - tests\n  - rockspecs\n'}
        def run(command, **kwargs):
            tree = '100644 blob a\tLibDeflate.lua\0' + '100644 blob b\ttests/Test.lua\0' + '100644 blob b\ttests/LibCompress/LibCompress.lua\0' + '100644 blob c\t.pkgmeta\0'
            return subprocess.CompletedProcess(command, 0, tree if 'ls-tree' in command else '', '')
        with patch.object(checker, 'run', side_effect=run), patch.object(checker.subprocess, 'run', side_effect=lambda command, **kwargs: subprocess.CompletedProcess(command, 0, blobs[command[-1]], b'')):
            remote = checker.upstream_files({'url': 'repo'}, ('git-commit', 'c' * 40))
        self.assertEqual(remote, {'LibDeflate.lua': runtime})
        code, output = CheckerTests().content_report(remote, remote)
        self.assertEqual(code, 0)
        self.assertIn('current=1 | accepted-drift=0 | pending=0 | DRIFT=0 | UNKNOWN=0', output)

    def test_ignores_are_exact_paths_not_global_test_exclusion(self):
        files = {'tests/Test.lua': b'test', 'other/tests/A.lua': b'keep', 'tests2.lua': b'keep'}
        self.assertEqual(checker.packaged_files(files), files)
        self.assertEqual(set(checker.packaged_files(files, b'ignore:\n  - tests\n')), {'other/tests/A.lua', 'tests2.lua'})

    def test_unsupported_ignore_is_unknown(self):
        for metadata in [b'ignore: [tests]', b'ignore:\n  - "tests"', b'ignore:\n  - **/tests', b'ignore:\n  - ../tests', b'ignore:\n- tests', b'"ignore":\n  - tests', b'<<: *defaults']:
            with self.assertRaises(RuntimeError):
                checker.packaged_files({'A.lua': b'code'}, metadata)
        code, output = CheckerTests().content_report({}, {}, failure=RuntimeError('Unsupported external pkgmeta ignore rule'))
        self.assertEqual(code, 1)
        self.assertIn('DRIFT=0 | UNKNOWN=1', output)

    def test_libdurability_missing_xml_is_drift_not_update(self):
        lua = b'LibStub:NewLibrary("LibDurability", 4)'
        with patch.object(checker, 'short_name', return_value='LibDurability'):
            code, output = CheckerTests().content_report({'LibDurability.lua': lua}, {'LibDurability.lua': lua, 'LibDurability.xml': b'<Ui/>'})
        self.assertEqual(code, 1)
        self.assertIn('pending=0 | DRIFT=1 | UNKNOWN=0', output)
        self.assertNotIn('update available', output)


class AcceptedDriftTests(unittest.TestCase):
    def fixtures(self, name):
        path = 'Libs/' + name
        entry = {'url': 'https://repos.wowace.com/wow/' + name + '/trunk'}
        if name == 'LibStub':
            entry['tag'] = '1.0'
            lua = b'local LIBSTUB_MAJOR, LIBSTUB_MINOR = "LibStub", 2'
        else:
            lua = b'LibStub:NewLibrary("LibDurability", 4)'
        resolved = ('svn-rev', '72')
        local = {name + '.lua': lua, 'helper.lua': b'audited helper'}
        upstream = dict(local, **{'load.xml': b'<Ui/>'})
        return path, entry, resolved, local, upstream

    def report(self, name='LibStub', mutate=None, failure=None, config='exact', lookup_failure=None, exact_changed_baseline=False):
        path, entry, resolved, local, upstream = self.fixtures(name)
        baseline = checker.drift_record(path, entry, resolved, local, upstream)
        if mutate:
            path, entry, resolved = mutate(path, entry, resolved, local, upstream)
        if exact_changed_baseline:
            baseline = checker.drift_record(path, entry, resolved, local, upstream)
        output = io.StringIO()
        with tempfile.TemporaryDirectory() as directory:
            location = Path(directory) / 'baselines.json'
            if config != 'absent':
                location.write_text('{' if config == 'invalid' else json.dumps({'schema': 1, 'baselines': [baseline]}))
            with patch.object(checker, 'DRIFT_BASELINES_PATH', location), patch.object(sys, 'argv', ['checker']), patch.object(checker, 'parse_externals', return_value={path: entry}), patch.object(checker, 'load_lockfile', return_value={}), patch.object(checker, 'resolve_upstream_version', return_value=resolved, side_effect=lookup_failure), patch.object(checker, 'relevant_files', return_value=local), patch.object(checker, 'upstream_files', return_value=upstream, side_effect=failure), patch.object(checker, 'run', return_value=subprocess.CompletedProcess([], 0, 'new-features', '')), contextlib.redirect_stdout(output), contextlib.redirect_stderr(io.StringIO()):
                code = checker.main()
        return code, output.getvalue()

    def test_exact_libstub_and_libdurability_baselines_are_accepted(self):
        for name in ['LibStub', 'LibDurability']:
            with self.subTest(name=name):
                code, output = self.report(name)
                self.assertEqual(code, 0)
                self.assertIn(name + ': accepted-drift;', output)
                self.assertIn('current=0 | accepted-drift=1 | pending=0 | DRIFT=0 | UNKNOWN=0', output)

    def test_local_and_upstream_content_paths_added_removed_invalidate(self):
        for side in ['local', 'upstream']:
            for change in ['content', 'added', 'removed', 'renamed']:
                def mutate(path, entry, resolved, local, upstream):
                    files = local if side == 'local' else upstream
                    if change == 'content':
                        files['LibStub.lua'] += b'\n-- changed'
                    elif change == 'added':
                        files['extra.lua'] = b'extra'
                    elif change == 'removed':
                        del files['helper.lua']
                    else:
                        files['renamed.lua'] = files.pop('helper.lua')
                    return path, entry, resolved
                with self.subTest(side=side, change=change):
                    code, output = self.report(mutate=mutate)
                    self.assertEqual(code, 1)
                    self.assertIn('accepted-drift=0 | pending=0 | DRIFT=1 | UNKNOWN=0', output)

    def test_identity_changes_are_not_accepted(self):
        for field in ['source', 'tag', 'version', 'snapshot_source', 'path', 'kind']:
            def mutate(path, entry, resolved, local, upstream):
                if field == 'source':
                    entry['url'] += '/different'
                elif field == 'tag':
                    entry['tag'] = '2.0'
                elif field == 'snapshot_source':
                    entry['_snapshot_url'] = entry['url'] + '/different'
                elif field == 'version':
                    resolved = (resolved[0], '73')
                elif field == 'kind':
                    resolved = ('git-tag', resolved[1])
                else:
                    path = 'Elsewhere/LibStub'
                return path, entry, resolved
            code, output = self.report(mutate=mutate)
            self.assertEqual(code, 1)
            self.assertIn('accepted-drift=0 | pending=0 | DRIFT=1 | UNKNOWN=0', output)

    def test_proven_minor_advance_bypasses_acceptance(self):
        def mutate(path, entry, resolved, local, upstream):
            upstream['LibStub.lua'] = upstream['LibStub.lua'].replace(b'2', b'3')
            return path, entry, resolved
        code, output = self.report(mutate=mutate, exact_changed_baseline=True)
        self.assertEqual(code, 1)
        self.assertIn('accepted-drift=0 | pending=1 | DRIFT=0 | UNKNOWN=0', output)

    def test_network_parsing_comparison_failures_remain_unknown(self):
        for failure in [RuntimeError('network denied'), ValueError('invalid metadata'), subprocess.TimeoutExpired('svn', 60)]:
            code, output = self.report(failure=failure)
            self.assertEqual(code, 1)
            self.assertIn('accepted-drift=0 | pending=0 | DRIFT=0 | UNKNOWN=1', output)
        code, output = self.report(lookup_failure=RuntimeError('lookup denied'))
        self.assertEqual(code, 1)
        self.assertIn('UNKNOWN=1', output)
        code, output = self.report(config='invalid')
        self.assertEqual(code, 1)
        self.assertIn('UNKNOWN=1', output)

    def test_absent_baseline_remains_drift(self):
        code, output = self.report(config='absent')
        self.assertEqual(code, 1)
        self.assertIn('accepted-drift=0 | pending=0 | DRIFT=1 | UNKNOWN=0', output)

    def test_fingerprint_order_framing_and_paths(self):
        self.assertEqual(checker.payload_fingerprint({'b.lua': b'b', 'a.lua': b'a'}), checker.payload_fingerprint({'a.lua': b'a', 'b.lua': b'b'}))
        self.assertNotEqual(checker.payload_fingerprint({'a.lua': b'bc'}), checker.payload_fingerprint({'ab.lua': b'c'}))
        self.assertNotEqual(checker.payload_fingerprint({'a.lua': b'a'}), checker.payload_fingerprint({'b.lua': b'a'}))

    def test_configured_local_fingerprints_match_audited_payloads(self):
        data = json.loads(checker.DRIFT_BASELINES_PATH.read_text())
        self.assertEqual({record['path'] for record in data['baselines']}, {'Libs/LibStub', 'Libs/LibDurability'})
        for record in data['baselines']:
            self.assertEqual(record['local_sha256'], checker.payload_fingerprint(checker.relevant_files(ROOT / record['path'])))
            self.assertTrue(checker.accepted_drift(record))


class ProxyTests(unittest.TestCase):
    def test_bootstrap_extracts_downloads_without_global_install(self):
        original_read = Path.read_text
        with tempfile.TemporaryDirectory() as temporary:
            prefix = Path(temporary) / 'eui-svn'
            calls = []

            def read(path, *args, **kwargs):
                if str(path) == '/etc/os-release':
                    return 'ID=debian\nVERSION_CODENAME=trixie\n'
                return original_read(path, *args, **kwargs)

            def run(command, **kwargs):
                calls.append(command)
                if '--download-only' in command:
                    generation = sum('--download-only' in previous for previous in calls)
                    (prefix / f'apt/archives/svn-{generation}.deb').write_bytes(b'fixture')
                if command[:2] == ['dpkg-deb', '-x']:
                    self.assertEqual(Path(command[3]), prefix / 'root')
                    (Path(command[3]) / Path(command[2]).stem).write_bytes(b'extracted')
                return subprocess.CompletedProcess(command, 0, '', '')

            archives = prefix / 'apt/archives'
            (archives / 'partial').mkdir(parents=True)
            (archives / 'old.deb').write_bytes(b'old')
            (archives / 'keep.txt').write_bytes(b'keep')
            (archives / 'partial/keep.part').write_bytes(b'partial')
            with patch.object(bootstrap, 'PREFIX', prefix), patch.object(Path, 'read_text', read), patch.object(bootstrap.subprocess, 'run', side_effect=run), contextlib.redirect_stdout(io.StringIO()):
                bootstrap.bootstrap()
                residual = prefix / 'root/removed-in-new-version'
                residual.write_bytes(b'residual')
                (prefix / 'config/keep.txt').write_bytes(b'config')
                (prefix.parent / 'bin/keep.txt').write_bytes(b'bin')
                wrapper = (prefix / 'wrapper.py').read_bytes()
                bootstrap.bootstrap()
            self.assertFalse(residual.exists())
            self.assertEqual(sorted(path.name for path in (prefix / 'root').iterdir()), ['svn-2'])
            self.assertEqual((prefix / 'root/svn-2').read_bytes(), b'extracted')
            self.assertEqual((prefix / 'config/keep.txt').read_bytes(), b'config')
            self.assertEqual((prefix.parent / 'bin/keep.txt').read_bytes(), b'bin')
            self.assertEqual((prefix / 'wrapper.py').read_bytes(), wrapper)
            self.assertTrue((prefix.parent / 'bin/svn').exists())
            self.assertTrue(any(command[:2] == ['dpkg-deb', '-x'] for command in calls))
            self.assertTrue(all('--download-only' in command for command in calls if 'install' in command))
            self.assertFalse(any('sudo' in command or command[:2] == ['dpkg', '-i'] for command in calls))
            self.assertNotIn('proxy', (prefix / 'apt/apt.conf').read_text())
            extracted = [Path(command[2]).name for command in calls if command[:2] == ['dpkg-deb', '-x']]
            self.assertEqual(extracted, ['svn-1.deb', 'svn-2.deb'])
            self.assertEqual(sorted(path.name for path in archives.glob('*.deb')), ['svn-2.deb'])
            self.assertEqual((archives / 'keep.txt').read_bytes(), b'keep')
            self.assertEqual((archives / 'partial/keep.part').read_bytes(), b'partial')

    def test_proxy_is_explicit_and_not_persisted(self):
        command = bootstrap.svn_command(['info', 'https://repos.wowace.com/repo'], {'HTTPS_PROXY': 'http://proxy:8080'})
        self.assertIn('servers:global:http-proxy-host=proxy', command)
        self.assertIn('servers:global:http-proxy-port=8080', command)
        self.assertIn('--no-auth-cache', command)
        self.assertIn('--non-interactive', command)

    def test_lowercase_and_http_fallback(self):
        for name in ['HTTP_PROXY', 'http_proxy', 'https_proxy']:
            self.assertIn('servers:global:http-proxy-port=80', bootstrap.proxy_args({name: 'http://proxy'}))
        self.assertEqual(bootstrap.proxy_args({}), [])

    def test_credentials_and_unsupported_proxy_fail(self):
        for proxy in ['http://user:secret@proxy:8080', 'socks5://proxy:8080', 'broken']:
            with self.assertRaises(RuntimeError):
                bootstrap.proxy_args({'HTTPS_PROXY': proxy})

    def test_path_query_fragment_and_malformed_proxy_fail(self):
        for proxy in ['http://proxy/', 'http://proxy/path', 'http://proxy?x=1', 'http://proxy?', 'http://proxy#fragment', 'http://proxy#', 'http:///missing-host', 'http://proxy:bad', 'http://proxy:65536', 'http://proxy:0', 'http://proxy:', 'http://[broken', 'http://proxy host', ' http://proxy', 'http://proxy\n', 'http://bad..host', 'http://-bad', 'http://proxy\\path', 'http://@proxy', 'http://proxy%20host']:
            with self.subTest(proxy=proxy), self.assertRaisesRegex(RuntimeError, 'Invalid SVN proxy URL'):
                bootstrap.proxy_args({'HTTPS_PROXY': proxy})

    def test_valid_ipv6_http_proxy(self):
        arguments = bootstrap.proxy_args({'HTTPS_PROXY': 'http://[::1]:8080'})
        self.assertIn('servers:global:http-proxy-host=::1', arguments)
        self.assertIn('servers:global:http-proxy-port=8080', arguments)

    def test_invalid_port_cli_has_clear_error_without_traceback(self):
        import os
        env = dict(os.environ, HTTPS_PROXY='http://proxy:bad')
        result = subprocess.run([sys.executable, '-B', str(ROOT / '.tools/bootstrap_cloud_svn.py'), '--svn', 'info'], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('Invalid SVN proxy URL', result.stderr)
        self.assertNotIn('Traceback', result.stderr)


if __name__ == '__main__':
    unittest.main()
