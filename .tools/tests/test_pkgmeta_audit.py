"""Audit semantics and native Git previews in disposable repositories."""
import copy
import json
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '.tools'))
import audit_pkgmeta as audit

GIT = shutil.which('git')
PS = shutil.which('powershell')
META = {'package-as': 'EllesmereUI', 'ignore': ['Held'], 'move-folders': {},
        'externals': {}, 'enable-nolib-creation': 'no'}


class Semantics(unittest.TestCase):
    def setUp(self):
        self.v = {k: copy.deepcopy(META) for k in ('base', 'fork', 'incoming', 'proposed')}
        self.paths = {k: ['EllesmereUI.toc', 'Held/Held.toc'] for k in self.v}

    def report(self, **kwargs):
        return audit.compare(self.v, self.paths, **kwargs)

    def test_add_ignore(self):
        for k in ('incoming', 'proposed'):
            self.v[k]['ignore'].append('Other')
        self.assertFalse(self.report()['risks'])
        self.assertIn('/Other', self.report()['sections']['ignore']['incoming_added'])

    def test_remove_ignore(self):
        for k in ('incoming', 'proposed'):
            self.v[k]['ignore'] = []
        self.assertFalse(self.report()['risks'])
        self.assertIn('EllesmereUI', self.report()['distribution']['after'])

    def test_independent_fork_ignore_move_external(self):
        for k in ('fork', 'proposed'):
            self.v[k]['ignore'].append('Private')
            self.v[k]['move-folders']['EllesmereUI/Custom'] = 'Custom'
            self.v[k]['externals']['Libs/Custom'] = {'url': 'https://example.invalid/lib'}
        report = self.report()
        self.assertFalse(report['risks'])
        for section in ('ignore', 'move-folders', 'externals'):
            self.assertTrue(report['sections'][section]['preserved'])

    def test_wholesale_incoming_replacement_blocked(self):
        self.v['fork']['ignore'].append('Private')
        self.assertTrue(self.report()['risks'])

    def test_both_sides_modify_mapping(self):
        self.v['base']['move-folders']['EllesmereUI/Custom'] = 'A'
        self.v['fork']['move-folders']['EllesmereUI/Custom'] = 'B'
        self.v['incoming']['move-folders']['EllesmereUI/Custom'] = 'C'
        self.assertTrue(self.report()['risks'])

    def test_clean_text_merge_hides_custom_module(self):
        self.paths['fork'].append('Custom/Custom.toc')
        self.paths['proposed'].append('Custom/Custom.toc')
        for k in ('incoming', 'proposed'):
            self.v[k]['ignore'].append('Custom')
        self.assertTrue(self.report()['risks'])

    def test_explicit_retention_blocks_removal(self):
        for k in ('incoming', 'proposed'):
            self.v[k]['ignore'] = []
        self.assertTrue(self.report(retained=['Held'])['risks'])
        self.assertTrue(self.report(touched=['Held'])['risks'])

    def test_inherited_module_with_custom_lua_is_protected(self):
        for k in ('incoming', 'proposed'):
            self.v[k]['ignore'].append('Existing')
        self.assertTrue(self.report(fork_changes=['Existing/main.lua'])['risks'])

    def test_order_is_not_functional(self):
        for v in self.v.values():
            v['ignore'].append('Other')
        self.v['proposed']['ignore'].reverse()
        self.assertFalse(self.report()['semantic_change'])

    def test_candidate_digest_preserves_checkout_newline_compatibility(self):
        self.assertEqual(audit.content_digest(b'package-as: EllesmereUI\n'),
                         audit.content_digest(b'\xef\xbb\xbfpackage-as: EllesmereUI\r\n'))
        self.assertNotEqual(audit.content_digest(b'ignore:\n'), audit.content_digest(b'ignore:\n  - Held\n'))

    def test_fork_removal_not_silently_reintroduced(self):
        self.v['fork']['ignore'] = []
        self.assertTrue(self.report()['risks'])

    def test_merge_tree_error_is_not_a_candidate(self):
        result = subprocess.CompletedProcess([], 128, b'f' * 40 + b'\0')
        with self.assertRaisesRegex(ValueError, 'failed'):
            audit.merge_candidate(result)

    def test_conflict_paths_must_be_complete(self):
        for data in (b'f' * 40 + b'\0', b'f' * 40 + b'\0\0'):
            with self.assertRaises(ValueError):
                audit.merge_candidate(subprocess.CompletedProcess([], 1, data))


@unittest.skipUnless(GIT and PS, 'Native Git and Windows PowerShell are required')
class GitPreview(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='eui-git-audit-test-')
        self.root = Path(self.temp.name)
        self.git('init', '-b', 'retail')
        # These identities belong exclusively to synthetic test history.
        self.git('config', 'user.name', 'Packaging Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'commit.gpgSign', 'false')
        self.git('config', 'core.autocrlf', 'false')
        self.meta = ('package-as: EllesmereUI\nmove-folders:\n'
                     '  EllesmereUI/Held: Held\n  EllesmereUI/Existing: Existing\nignore:\n  - Held\n')
        self.write('.pkgmeta', self.meta)
        self.write('EllesmereUI.toc', 'main.lua\n')
        self.write('Held/Held.toc', 'main.lua\n')
        self.write('Existing/Existing.toc', 'main.lua\n')
        self.policy = {'schema': 1, 'targets': {'new-features': '120105', '12.1.7-PTR-features': '120107'},
                       'camelot_interface': '16001', 'classes': {
                           kind: {'reason': 'Fixture', 'paths': []} for kind in ('retail', 'camelot', 'shared', 'embedded')}}
        self.policy['classes']['shared']['paths'] = ['EllesmereUI.toc', 'Held/Held.toc', 'Existing/Existing.toc']
        self.write('.tools/toc_policy.json', json.dumps(self.policy))
        self.commit('Base')
        self.git('branch', 'incoming')
        self.git('branch', 'ptr')
        target = self.root / '.tools/install'
        target.mkdir(parents=True)
        for name in ('read-pkgmeta.ps1', 'eui-package.ps1', 'eui-install-safety.ps1'):
            shutil.copyfile(ROOT / '.tools/install' / name, target / name)

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args):
        return audit.command([GIT, '-C', str(self.root), *args], self.root).stdout.decode().strip()

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')

    def commit(self, message):
        self.git('add', '.pkgmeta', '*.toc', '.tools/toc_policy.json')
        self.git('commit', '-m', message)

    def classify(self, path, kind):
        policy = json.loads((self.root / '.tools/toc_policy.json').read_text())
        policy['classes'][kind]['paths'].append(path)
        self.write('.tools/toc_policy.json', json.dumps(policy))

    def invoke(self, dest='retail', source='incoming', **kwargs):
        before = self.git('show-ref'), self.git('status', '--porcelain=v1'), (self.root / '.pkgmeta').read_bytes()
        result = audit.audit(self.root, GIT, PS, dest, source, **kwargs)
        after = self.git('show-ref'), self.git('status', '--porcelain=v1'), (self.root / '.pkgmeta').read_bytes()
        self.assertEqual(before, after, 'Audit mutated refs/index/checkout')
        return result

    def incoming(self, text):
        self.git('switch', 'incoming')
        self.write('.pkgmeta', text)
        self.commit('Incoming')
        self.git('switch', 'retail')

    def test_noop(self):
        self.assertEqual(self.invoke()['status'], 'no-op')

    def test_fast_forward_removal(self):
        self.incoming(self.meta.replace('  - Held\n', ''))
        result = self.invoke()
        self.assertEqual(result['status'], 'safe')
        self.assertTrue(result['fast_forward'])
        self.assertIn('-  - Held', result['textual_diffs']['incoming'])
        self.assertIn('-  - Held', result['textual_diffs']['proposed'])

    def test_fast_forward_blocks_before_mutation(self):
        self.incoming(self.meta.replace('  - Held\n', ''))
        self.assertEqual(self.invoke(retained=['Held'])['status'], 'decision-required')

    def test_divergent_merge_preserves_independent_fork_mapping(self):
        self.write('Custom/Custom.toc', 'main.lua\n')
        self.classify('Custom/Custom.toc', 'shared')
        self.write('.pkgmeta', self.meta.replace('move-folders:', 'move-folders:\n  EllesmereUI/Custom: Custom'))
        self.commit('Fork mapping')
        self.incoming(self.meta + '  - Other\n')
        result = self.invoke()
        self.assertEqual(result['status'], 'safe')
        self.assertTrue(result['sections']['move-folders']['preserved'])

    def test_same_text_region_conflict_blocks(self):
        self.write('.pkgmeta', self.meta + '  - Private\n')
        self.commit('Fork exclusion')
        self.incoming(self.meta + '  - Other\n')
        with self.assertRaisesRegex(ValueError, 'conflict'):
            self.invoke()

    def test_runtime_conflict_does_not_block_clean_packaging_audit(self):
        self.write('Existing/main.lua', '-- base\n')
        self.git('add', 'Existing/main.lua')
        self.commit('Shared runtime base')
        self.git('branch', '-f', 'incoming', 'HEAD')
        self.write('Existing/main.lua', '-- fork\n')
        self.git('add', 'Existing/main.lua')
        self.commit('Fork runtime')
        self.git('switch', 'incoming')
        self.write('Existing/main.lua', '-- incoming\n')
        self.write('.pkgmeta', self.meta + '  - Other\n')
        self.git('add', 'Existing/main.lua')
        self.commit('Incoming runtime and packaging')
        self.git('switch', 'retail')
        result = self.invoke()
        self.assertEqual(result['status'], 'safe')
        self.assertEqual(result['pending_conflicts'], ['Existing/main.lua'])
        self.assertIn('/Other', result['sections']['ignore']['incoming_added'])

    def test_runtime_conflict_does_not_bypass_distribution_risk(self):
        self.test_runtime_conflict_does_not_block_clean_packaging_audit()
        self.git('switch', 'incoming')
        self.write('.pkgmeta', self.meta + '  - Existing\n')
        self.commit('Exclude customized module')
        self.git('switch', 'retail')
        result = self.invoke()
        self.assertEqual(result['status'], 'decision-required')
        self.assertEqual(result['pending_conflicts'], ['Existing/main.lua'])

    def test_inherited_module_with_lua_customization_blocks_ignore(self):
        self.write('Existing/main.lua', '-- fork customization\n')
        self.git('add', 'Existing/main.lua')
        self.commit('Fork runtime customization')
        self.incoming(self.meta + '  - Existing\n')
        self.assertEqual(self.invoke()['status'], 'decision-required')

    def test_colliding_proposed_layout_blocks_before_fast_forward(self):
        self.incoming(self.meta.replace('EllesmereUI/Existing: Existing', 'EllesmereUI/Existing: Held'))
        with self.assertRaisesRegex(ValueError, 'Colliding'):
            self.invoke()

    def test_post_release_commits_excluded(self):
        self.incoming(self.meta + '  - Released\n')
        release = self.git('rev-parse', 'incoming')
        self.git('switch', 'incoming')
        self.write('.pkgmeta', self.meta + '  - Released\n  - NotEligible\n')
        self.commit('Post release')
        self.git('switch', 'retail')
        result = self.invoke(source=release)
        self.assertNotIn('/NotEligible', result['sections']['ignore']['incoming_added'])

    def test_retail_to_ptr(self):
        self.write('.pkgmeta', self.meta + '  - RetailOnly\n')
        self.commit('Retail exclusion')
        self.assertEqual(self.invoke('ptr', 'retail')['status'], 'safe')

    def test_format_only(self):
        self.incoming('# comment\n' + self.meta + '\n')
        result = self.invoke()
        self.assertFalse(result['semantic_change'])

    def test_embedded_arbitrary_path_preserved_across_merge(self):
        self.write('Existing/vendor/Library.toc', 'vendor.lua\n')
        self.classify('Existing/vendor/Library.toc', 'embedded')
        self.commit('Classify embedded library outside Libs')
        self.incoming(self.meta + '  - Other\n')
        result = self.invoke()
        self.assertEqual(result['status'], 'safe')
        self.assertNotIn('Library', result['distribution']['after'])
        self.assertEqual(set(result['policy_sources']), {'base', 'fork', 'incoming', 'proposed'})

    def test_unknown_arbitrary_manifest_is_not_embedded(self):
        self.git('switch', 'incoming')
        self.write('Existing/vendor/Unknown.toc', 'vendor.lua\n')
        self.write('.pkgmeta', self.meta + '  - Other\n')
        self.commit('Unknown nested manifest')
        self.git('switch', 'retail')
        with self.assertRaisesRegex(ValueError, 'Unknown manifests'):
            self.invoke()

    def test_independent_nested_addon_requires_mapping(self):
        self.git('switch', 'incoming')
        self.write('Existing/vendor/Independent.toc', 'main.lua\n')
        self.classify('Existing/vendor/Independent.toc', 'shared')
        self.write('.pkgmeta', self.meta + '  - Other\n')
        self.commit('Independent nested addon')
        self.git('switch', 'retail')
        with self.assertRaisesRegex(ValueError, 'requires a move mapping'):
            self.invoke()

    def test_unknown_toc_inside_libs_is_not_implicitly_embedded(self):
        self.git('switch', 'incoming')
        self.write('Libs/Unknown/Unknown.toc', 'vendor.lua\n')
        self.write('.pkgmeta', self.meta + '  - Other\n')
        self.commit('Unknown manifest in Libs')
        self.git('switch', 'retail')
        with self.assertRaisesRegex(ValueError, 'Unknown manifests'):
            self.invoke()

    def test_upstream_without_fork_policy_uses_only_explicit_fork_classes(self):
        self.git('rm', '.tools/toc_policy.json')
        self.git('commit', '-m', 'Baseline without fork tooling')
        self.git('branch', '-f', 'incoming', 'HEAD')
        self.write('.tools/toc_policy.json', json.dumps(self.policy))
        self.commit('Maintain explicit fork policy')
        self.git('switch', 'incoming')
        self.write('.pkgmeta', self.meta + '  - Other\n')
        self.git('add', '.pkgmeta')
        self.git('commit', '-m', 'Upstream packaging change')
        self.git('switch', 'retail')
        result = self.invoke()
        self.assertEqual(result['status'], 'safe')
        for key in ('base', 'incoming'):
            self.assertIn('policy absent', result['policy_sources'][key])
        self.assertEqual(result['policy_sources']['proposed'], 'proposed')


if __name__ == '__main__':
    unittest.main(verbosity=2)
