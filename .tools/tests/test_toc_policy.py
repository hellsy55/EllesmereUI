"""TOC and release regressions in disposable trees; no network or WoW required."""
import codecs
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '.tools'))
import normalize_tocs as tocs
import release_manifest as release

LIVE = 'new-features'
PTR = '12.1.7-PTR-features'
BODY = (b'## SavedVariables: KeepDB\n## Dependencies: EllesmereUI\n'
        b'## LoadOnDemand: 1\n## DefaultState: disabled\n'
        b'# Preserve this comment\nFirst.lua [AllowLoadGameType standard]\nSecond.lua\n')


class HeaderTests(unittest.TestCase):
    def normalize(self, data, kind='retail', retail='120105'):
        return tocs.normalize(data, kind, retail, '16001')

    def test_client_matrix(self):
        for retail in ('120105', '120107'):
            for kind, expected in [('retail', retail), ('camelot', '16001'),
                                   ('shared', retail + ', 16001')]:
                with self.subTest(retail=retail, kind=kind):
                    result = self.normalize(b'## Interface: 120000, 16001\n' + BODY, kind, retail)
                    self.assertIn(('## Interface: ' + expected + '\n').encode(), result)
                    self.assertTrue(result.endswith(BODY))

    def test_retail_removes_forever_and_old_versions(self):
        result = self.normalize(b'## Interface: 120000, 120001, 120005, 120007, 120100, 120105, 16001\n')
        self.assertEqual(result, b'## AllowLoadGameType: standard\n## Interface: 120105\n')

    def test_camelot_removes_retail(self):
        result = self.normalize(b'## Interface: 120105, 16001\n', 'camelot')
        self.assertEqual(result, b'## AllowLoadGameType: camelot\n## Interface: 16001\n')

    def test_duplicate_headers_rejected(self):
        for key in ('Interface', 'AllowLoadGameType', 'ExcludeLoadGameType', 'SavedVariables'):
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'Duplicate'):
                self.normalize(f'## {key}: x\n## {key.lower()}: y\n'.encode())

    def test_conflicting_exclusion(self):
        for kind, value in [('retail', 'standard'), ('camelot', 'camelot'),
                            ('shared', 'standard, camelot')]:
            with self.subTest(kind=kind), self.assertRaisesRegex(ValueError, 'ExcludeLoadGameType'):
                self.normalize(f'## Interface: 1\n## ExcludeLoadGameType: {value}\n'.encode(), kind)

    def test_unrelated_exclusion_preserved(self):
        data = b'## ExcludeLoadGameType: classic\n'
        self.assertIn(data, self.normalize(b'## Interface: 1\n' + data))

    def test_allow_corrected_only_for_exclusive_clients(self):
        data = b'## Interface: 1\n## AllowLoadGameType: camelot\n'
        self.assertIn(b'## AllowLoadGameType: standard\n', self.normalize(data))
        with self.assertRaisesRegex(ValueError, 'Shared manifest'):
            self.normalize(data, 'shared')

    def test_preserve_bom_line_endings_and_body(self):
        for newline in (b'\n', b'\r\n'):
            for bom in (b'', codecs.BOM_UTF8):
                with self.subTest(newline=newline, bom=bom):
                    body = BODY.replace(b'\n', newline)
                    data = bom + b'## Interface: 1' + newline + body
                    result = self.normalize(data)
                    self.assertEqual(result.startswith(codecs.BOM_UTF8), bool(bom))
                    self.assertTrue(result.endswith(body))
                    self.assertEqual(result.count(b'\r\n'), result.count(b'\n') if newline == b'\r\n' else 0)
                    self.assertEqual(self.normalize(result), result)

    def test_mixed_line_endings_and_no_final_newline(self):
        data = b'## Interface: 1\r\n## AllowLoadGameType: standard\nLast.lua'
        self.assertEqual(self.normalize(data), data.replace(b'Interface: 1\r', b'Interface: 120105\r'))

    def test_embedded_vendor_headers_not_rewritten(self):
        data = b'## Interface: 99999\n## Version: @project-version@\nLibrary.lua\n'
        self.assertEqual(self.normalize(data, 'embedded'), data)

    def test_conflicts_and_client_overrides_rejected(self):
        for line in (b'<<<<<<< HEAD\n', b'=======\n', b'>>>>>>> incoming\n', b'## Interface-Retail: 99999\n'):
            with self.subTest(line=line), self.assertRaises(ValueError):
                self.normalize(b'## Interface: 1\n' + line)

    def test_invalid_encoding_rejected(self):
        with self.assertRaises(ValueError):
            self.normalize(b'## Interface: 1\n\xff')

    def test_forever_skin_and_held_back_metadata_preserved(self):
        skin = b'EllesmereUIBlizzardSkin_GroupFinderForever.lua\n'
        result = self.normalize(b'## Interface: 120105, 16001\n' + BODY + skin, 'shared', '120107')
        self.assertEqual(result, b'## Interface: 120107, 16001\n' + BODY + skin)


class TreeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.policy, self.classes = tocs.load_policy()
        for name, kind in self.classes.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(tocs.normalize(b'## Interface: 120105\n' + BODY, kind, '120105', '16001'))
        shutil.copyfile(ROOT / '.pkgmeta', self.root / '.pkgmeta')

    def run_tool(self, mode='check', target=LIVE):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return tocs.run(self.root, target, mode)

    def snapshot(self):
        return {p.relative_to(self.root).as_posix(): (p.read_bytes(), p.stat().st_mtime_ns)
                for p in self.root.rglob('*') if p.is_file()}

    def test_check_does_not_mutate_even_with_drift(self):
        before = self.snapshot()
        self.assertEqual(self.run_tool(target=PTR), 1)
        self.assertEqual(self.snapshot(), before)

    def test_fix_is_idempotent_including_timestamps(self):
        self.assertEqual(self.run_tool('fix', PTR), 0)
        before = self.snapshot()
        self.assertEqual(self.run_tool('fix', PTR), 0)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.run_tool(target=PTR), 0)

    def test_retail_to_ptr_integration(self):
        self.assertEqual(self.run_tool('fix', PTR), 0)
        # Incoming Retail manifests overwrite the integrated destination.
        for name, kind in self.classes.items():
            if kind != 'embedded':
                p = self.root / name
                p.write_bytes(tocs.normalize(p.read_bytes(), kind, '120105', '16001'))
        self.assertEqual(self.run_tool(target=PTR), 1)
        self.assertEqual(self.run_tool('fix', PTR), 0)
        self.assertEqual(self.run_tool(target=PTR), 0)

    def test_unknown_nested_uppercase_manifest_blocks_all_writes(self):
        path = self.root / 'New/Libs/Unknown.TOC'
        path.parent.mkdir(parents=True)
        path.write_bytes(b'## Interface: 1\n')
        before = self.snapshot()
        self.assertEqual(self.run_tool('fix', PTR), 1)
        self.assertEqual(self.snapshot(), before)

    def test_missing_manifest_fails(self):
        (self.root / 'EllesmereUI.toc').unlink()
        self.assertEqual(self.run_tool(), 1)

    def test_unknown_branch_fails_without_writes(self):
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, 'Unknown target'):
            self.run_tool('fix', 'main')
        self.assertEqual(self.snapshot(), before)

    def test_generated_output_and_cache_are_excluded(self):
        for name in ('.release', '.pkgmeta-cache'):
            (self.root / name).mkdir()
            (self.root / name / 'Unknown.toc').write_bytes(b'anything')
        self.assertEqual(self.run_tool(), 0)

    def test_duplicate_header_prevents_other_repairs(self):
        path = self.root / 'EllesmereUI.toc'
        path.write_bytes(path.read_bytes() + b'## Interface: 1\n')
        before = self.snapshot()
        self.assertEqual(self.run_tool('fix', PTR), 1)
        self.assertEqual(self.snapshot(), before)

    def test_atomic_replace_failure_preserves_original(self):
        path = self.root / 'EllesmereUI.toc'
        before = self.snapshot()
        with patch.object(tocs.os, 'replace', side_effect=OSError('simulated disk failure')):
            with self.assertRaises(OSError):
                tocs.atomic_write(path, b'new')
        self.assertEqual(self.snapshot(), before)

    def test_explicit_next_patch_configuration(self):
        config = self.root / 'policy.json'
        self.policy['targets'][LIVE] = '120200'
        config.write_text(json.dumps(self.policy), encoding='utf-8')
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(tocs.run(self.root, LIVE, 'fix', config), 0)
            self.assertEqual(tocs.run(self.root, LIVE, 'check', config), 0)

    def test_duplicate_policy_classification_rejected(self):
        config = self.root / 'policy.json'
        self.policy['classes']['retail']['paths'].append('EllesmereUI.toc')
        config.write_text(json.dumps(self.policy), encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'more than once'):
            tocs.load_policy(config)

    def make_archive(self, change=None, omit=None, extra=None):
        archive = self.root / 'fixture.zip'
        mapped, _ = release.package_layout(self.root)
        with zipfile.ZipFile(archive, 'w') as output:
            for source in self.classes:
                name = mapped(source)
                if name and source != omit:
                    data = (self.root / source).read_bytes()
                    output.writestr(name, change(source, data) if change else data)
            if extra:
                output.writestr(*extra)
        return archive

    def test_release_archive_valid_and_external_coverage_reported(self):
        archive = self.make_archive(extra=('EllesmereUI/Libs/LibSharedMedia-3.0/Vendor.toc', b'## Interface: 1'))
        with contextlib.redirect_stdout(io.StringIO()) as log:
            release.check_archive(self.root, LIVE, archive)
        self.assertIn('external manifests excluded', log.getvalue())

    def test_release_archive_drift_and_wrong_target(self):
        archive = self.make_archive(change=lambda p, d: d.replace(b'120105', b'120107') if p == 'EllesmereUI.toc' else d)
        with self.assertRaisesRegex(ValueError, 'drift'):
            release.check_archive(self.root, LIVE, archive)
        with self.assertRaisesRegex(ValueError, 'drift'):
            release.check_archive(self.root, PTR, archive)

    def test_release_archive_missing_manifest(self):
        archive = self.make_archive(omit='EllesmereUI.toc')
        with self.assertRaisesRegex(ValueError, 'Missing'):
            release.check_archive(self.root, LIVE, archive)

    def test_release_archive_rejects_new_or_held_back_manifest(self):
        for name in ('Unknown/Unknown.toc', 'EllesmereUI/EllesmereUILoadoutManager/EllesmereUILoadoutManager.toc'):
            with self.subTest(name=name):
                archive = self.make_archive(extra=(name, b'## Interface: 120105'))
                with self.assertRaisesRegex(ValueError, 'Unclassified or excluded'):
                    release.check_archive(self.root, LIVE, archive)

    def test_release_archive_detects_removed_file_reference(self):
        archive = self.make_archive(change=lambda p, d: d.replace(b'Second.lua\n', b'') if p == 'EllesmereUI.toc' else d)
        with self.assertRaisesRegex(ValueError, 'changed manifest content'):
            release.check_archive(self.root, LIVE, archive)

    def test_release_archive_duplicate_path(self):
        with contextlib.redirect_stderr(io.StringIO()):
            archive = self.make_archive(extra=('ellesmereui/ELLESMEREUI.toc', b''))
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            release.check_archive(self.root, LIVE, archive)


class GitTests(unittest.TestCase):
    run_tool = TreeTests.run_tool

    def setUp(self):
        TreeTests.setUp(self)
        release.git(self.root, 'init', '-q', '-b', LIVE)
        release.git(self.root, 'config', 'user.name', 'Fixture Author')
        release.git(self.root, 'config', 'user.email', 'fixture@example.invalid')
        release.git(self.root, 'add', '.')
        release.git(self.root, 'commit', '-qm', 'Fixture (test): initialize manifests')
        release.git(self.root, 'branch', PTR)

    def annotate(self, name='v-test', message='EUI-Target: ' + LIVE):
        release.git(self.root, 'tag', '-a', name, '-m', message)

    def test_detached_head_with_explicit_target(self):
        release.git(self.root, 'checkout', '--detach', '-q')
        self.assertEqual(self.run_tool(), 0)

    def test_tag_helper_dry_run_and_creation(self):
        self.assertIn('dry run', release.prepare_tag(self.root, LIVE, 'v-test'))
        self.assertEqual(release.git(self.root, 'tag', '--list'), '')
        release.prepare_tag(self.root, LIVE, 'v-test', True)
        self.assertEqual(release.tag_target(self.root, 'v-test'), LIVE)
        with self.assertRaisesRegex(ValueError, 'already exists'):
            release.prepare_tag(self.root, LIVE, 'v-test', True)

    def test_valid_annotated_tag_detached_remote_ancestry(self):
        self.annotate()
        release.git(self.root, 'update-ref', 'refs/remotes/origin/' + LIVE, 'HEAD')
        release.git(self.root, 'checkout', '--detach', '-q')
        self.assertEqual(release.tag_target(self.root, 'v-test', True), LIVE)

    def test_lightweight_tag_rejected(self):
        release.git(self.root, 'tag', 'v-light')
        with self.assertRaisesRegex(ValueError, 'annotated'):
            release.tag_target(self.root, 'v-light')

    def test_bad_annotations_rejected(self):
        for i, message in enumerate(['No target', 'EUI-Target: main', 'EUI-Target: ' + LIVE + '\nEUI-Target: ' + PTR]):
            self.annotate('v-' + str(i), message)
            with self.assertRaises(ValueError):
                release.tag_target(self.root, 'v-' + str(i))

    def test_tag_with_matching_ancestry_but_wrong_client_rejected(self):
        self.annotate(message='EUI-Target: ' + PTR)
        with self.assertRaisesRegex(ValueError, 'drift'):
            release.tag_target(self.root, 'v-test')

    def test_tag_not_in_destination_branch_rejected(self):
        before = release.git(self.root, 'rev-parse', 'HEAD')
        release.git(self.root, 'checkout', '-qb', 'other')
        release.git(self.root, 'commit', '--allow-empty', '-qm', 'Fixture (test): unrelated tip')
        self.annotate()
        self.assertEqual(release.git(self.root, 'rev-parse', LIVE), before)
        with self.assertRaisesRegex(ValueError, 'merge-base failed'):
            release.tag_target(self.root, 'v-test')

    def test_tag_commit_different_from_checkout_rejected(self):
        self.annotate()
        release.git(self.root, 'commit', '--allow-empty', '-qm', 'Fixture (test): advance')
        with self.assertRaisesRegex(ValueError, 'differs'):
            release.tag_target(self.root, 'v-test')

    def test_dirty_checkout_rejected(self):
        self.annotate()
        (self.root / 'untracked.txt').write_text('preserve', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'clean checkout'):
            release.tag_target(self.root, 'v-test')

    def test_missing_remote_ref_rejected(self):
        self.annotate()
        with self.assertRaises(ValueError):
            release.tag_target(self.root, 'v-test', True)

    def test_unmerged_non_toc_index_blocks_normalization(self):
        release.git(self.root, 'checkout', '-qb', 'other')
        (self.root / 'conflict.txt').write_text('other', encoding='utf-8')
        release.git(self.root, 'add', 'conflict.txt')
        release.git(self.root, 'commit', '-qm', 'Fixture (test): add other version')
        release.git(self.root, 'checkout', '-q', LIVE)
        (self.root / 'conflict.txt').write_text('local', encoding='utf-8')
        release.git(self.root, 'add', 'conflict.txt')
        release.git(self.root, 'commit', '-qm', 'Fixture (test): add local version')
        with self.assertRaises(ValueError):
            release.git(self.root, 'merge', '--no-commit', 'other')
        with self.assertRaisesRegex(ValueError, 'Unmerged index'):
            self.run_tool('fix', PTR)


class WorkflowTests(unittest.TestCase):
    def test_ci_pr_base_and_push_destination(self):
        policy, _ = tocs.load_policy()
        for target in (LIVE, PTR):
            self.assertEqual(tocs.ci_target({'ref': 'refs/heads/' + target}, policy), target)
            self.assertEqual(tocs.ci_target({'ref': 'refs/pull/1/merge', 'pull_request':
                                           {'base': {'ref': target}, 'head': {'ref': 'untrusted'}}}, policy), target)
        for event in ({'ref': 'refs/heads/main'}, {'ref': 'refs/tags/v1'}, {}):
            with self.assertRaises(ValueError):
                tocs.ci_target(event, policy)

    def test_workflow_contracts(self):
        ci = (ROOT / '.github/workflows/toc-policy.yml').read_text(encoding='utf-8')
        self.assertEqual(ci.count('branches: [new-features, 12.1.7-PTR-features]'), 2)
        self.assertIn('check --github-event "$GITHUB_EVENT_PATH"', ci)
        self.assertNotIn('normalize_tocs.py fix', ci)
        workflow = (ROOT / '.github/workflows/release.yml').read_text(encoding='utf-8')
        self.assertLess(workflow.index('preflight --tag'), workflow.index('--publish --tag'))
        self.assertIn('fetch-depth: 0', workflow)
        skill = (ROOT / '.agents/skills/eui-update/SKILL.md').read_text(encoding='utf-8')
        for required in ('fix --target <destination-branch>', 'check --target <destination-branch>',
                         'unmerged', 'immediately before every commit', 'no-op', 'second `fix`'):
            self.assertIn(required, skill)

    def test_packager_hash_and_boundary_fail_closed(self):
        with self.assertRaisesRegex(ValueError, 'checksum'):
            release.protect_packager(b'untrusted')
        for data in (b'no boundary', release.BOUNDARY * 2):
            with patch.object(release, 'PACKAGER_SHA256', hashlib.sha256(data).hexdigest()):
                with self.assertRaisesRegex(ValueError, 'boundary'):
                    release.protect_packager(data)

    def test_publication_sentinel_unreachable_on_archive_failure(self):
        bash = Path('C:/Program Files/Git/bin/bash.exe') if os.name == 'nt' else Path('/bin/bash')
        if not bash.is_file():
            self.skipTest('Bash is unavailable')
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / '.tools').mkdir()
            (root / '.tools/release_manifest.py').write_text(
                'import os,sys\nsys.exit(int(os.environ["FIXTURE_RESULT"]))\n', encoding='utf-8')
            data = b'archive=fixture.zip\nnolib_archive=\ntag=v-test\n' + release.BOUNDARY + b'echo PUBLISHED\n'
            with patch.object(release, 'PACKAGER_SHA256', hashlib.sha256(data).hexdigest()):
                script = release.protect_packager(data)
            self.assertEqual(script.count(release.GATE), 1)
            for status, requested in ((0, 'v-test'), (1, 'v-test'), (0, 'different-tag')):
                env = dict(os.environ, EUI_PYTHON=sys.executable, EUI_ROOT=root.as_posix(),
                           EUI_TARGET=LIVE, EUI_RELEASE_TAG=requested, FIXTURE_RESULT=str(status))
                result = subprocess.run([str(bash), '-s'], input=script, capture_output=True, env=env)
                expected = status if requested == 'v-test' else 1
                self.assertEqual(result.returncode, expected)
                self.assertEqual(result.stdout.count(b'PUBLISHED'), int(expected == 0))


if __name__ == '__main__':
    unittest.main()
