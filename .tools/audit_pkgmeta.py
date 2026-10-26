"""Read-only integration gate; Git computes the candidate in an isolated object store."""
import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import normalize_tocs as tocs


def command(argv, cwd, env=None, allowed=(0,)):
    result = subprocess.run(argv, cwd=cwd, env=env, capture_output=True, shell=False)
    if result.returncode not in allowed:
        raise ValueError(f'Command failed ({result.returncode}): {argv!r}\n' +
                         result.stdout.decode('utf-8', 'replace') + result.stderr.decode('utf-8', 'replace'))
    return result


def flatten(value, prefix=''):
    if isinstance(value, dict):
        return {k: v for key, item in value.items()
                for k, v in flatten(item, prefix + '/' + key).items()}
    if isinstance(value, list):
        return {prefix + '/' + item: True for item in value}
    return {prefix: value}


def content_digest(data):
    # Git checkout conversion may add CRLF; this is not a packaging change.
    return hashlib.sha256(data.decode('utf-8-sig').replace('\r\n', '\n').encode('utf-8')).hexdigest()


def ignored(path, meta):
    return any(path == rule or path.startswith(rule + '/') for rule in meta['ignore'])


def distribution(paths, meta):
    result = set()
    for path in paths:
        if ignored(path, meta):
            continue
        name = meta['package-as'] + '/' + path
        for source, dest in meta['move-folders'].items():
            if name == source or name.startswith(source + '/'):
                name = dest + name[len(source):]
                break
        result.add(name.split('/')[0])
    return sorted(result)


def mapped(path, meta):
    if ignored(path, meta):
        return None
    name = meta['package-as'] + '/' + path
    for source, dest in meta['move-folders'].items():
        if name == source or name.startswith(source + '/'):
            return dest + name[len(source):]
    return name


def suite_manifests(files, classification):
    found = {p for p in files if p.lower().endswith('.toc')
             and p.split('/')[0] not in tocs.SKIP_ROOTS}
    unknown = found - classification.keys()
    if unknown:
        raise ValueError('Unknown manifests; classify explicitly in toc_policy.json: ' + ', '.join(sorted(unknown)))
    return sorted(p for p in found if classification[p] != 'embedded')


def validate_layout(meta, files, classification):
    if meta['package-as'] != 'EllesmereUI':
        raise ValueError('Proposed package-as is incompatible with the installer')
    destinations = set()
    for source, dest in meta['move-folders'].items():
        if not source.startswith('EllesmereUI/') or '/' in dest or dest.casefold() == 'ellesmereui':
            raise ValueError('Invalid proposed folder move: ' + source)
        if dest.casefold() in destinations:
            raise ValueError('Colliding proposed move destination: ' + dest)
        destinations.add(dest.casefold())
        relative = source.removeprefix('EllesmereUI/')
        if not any(p.startswith(relative + '/') for p in files):
            raise ValueError('Missing proposed move source: ' + relative)
        for other in meta['move-folders']:
            if source != other and source.startswith(other + '/'):
                raise ValueError('Overlapping proposed moves')
    for path in suite_manifests(files, classification):
        name = mapped(path, meta)
        if name and len(name.split('/')) != 2:
            raise ValueError('Proposed addon requires a move mapping: ' + path)


def compare(versions, paths, retained=(), touched=(), fork_changes=()):
    base, fork, incoming, proposed = (versions[k] for k in ('base', 'fork', 'incoming', 'proposed'))
    report = {'sections': {}, 'risks': []}
    risks = report['risks']
    for section in sorted(set(base) | set(fork) | set(incoming) | set(proposed)):
        values = [flatten(meta.get(section, {})) for meta in (base, fork, incoming, proposed)]
        b, f, i, p = values
        custom = {k: v for k, v in f.items() if k not in b or b[k] != v}
        removed_custom = [k for k in b if k not in f]
        lost = [k for k, v in custom.items() if p.get(k) != v]
        lost += [k for k in removed_custom if k in p]
        report['sections'][section] = {
            'incoming_added': {k: v for k, v in i.items() if k not in b},
            'incoming_removed': {k: v for k, v in b.items() if k not in i},
            'incoming_modified': {k: [b[k], v] for k, v in i.items() if k in b and b[k] != v},
            'fork_custom': custom, 'fork_custom_removed': removed_custom,
            'preserved': {k: v for k, v in custom.items() if p.get(k) == v}, 'lost_or_modified': lost}
        risks.extend(f'{section}: fork customization changed: {key}' for key in lost)
        for key in set(b) & set(f) & set(i):
            if f[key] != b[key] and i[key] != b[key] and f[key] != i[key]:
                risks.append(f'{section}: both sides modified {key}')
    added = set(incoming['ignore']) - set(base['ignore'])
    removed = set(base['ignore']) - set(incoming['ignore'])
    for rule in removed:
        if rule in retained or rule in touched:
            risks.append('Removed ignore requires historical fork decision: ' + rule)
    # Protect both new modules and runtime customizations in inherited modules.
    custom_paths = (set(paths['fork']) - set(paths['base'])) | set(fork_changes)
    for key, value in fork['move-folders'].items():
        if base['move-folders'].get(key) != value:
            custom_paths.add(key.removeprefix(fork['package-as'] + '/'))
    for rule in added:
        if any(path == rule or path.startswith(rule + '/') for path in custom_paths):
            risks.append('New ignore overlaps fork customization: ' + rule)
    for path in fork_changes:
        if mapped(path, fork) != mapped(path, proposed):
            risks.append('Distribution changed for fork-customized path: ' + path)
    before = distribution(paths['fork'], fork)
    after = distribution(paths['proposed'], proposed)
    report['distribution'] = {'before': before, 'after': after,
                              'added': sorted(set(after) - set(before)),
                              'removed': sorted(set(before) - set(after))}
    report['semantic_change'] = flatten(fork) != flatten(proposed)
    report['risks'] = sorted(set(risks))
    return report


def audit(root, git, powershell, destination, source, retained=()):
    def run(*args, env=None, allowed=(0,)):
        return command([git, '-C', str(root), *args], root, env, allowed)
    def output(*args, **kwargs):
        return run(*args, **kwargs).stdout.decode('utf-8').strip()
    fork = output('rev-parse', '--verify', destination + '^{commit}')
    incoming = output('rev-parse', '--verify', source + '^{commit}')
    bases = output('merge-base', '--all', fork, incoming).splitlines()
    if len(bases) != 1:
        raise ValueError('Multiple merge bases require human review')
    base = bases[0]
    if run('merge-base', '--is-ancestor', incoming, fork, allowed=(0, 1)).returncode == 0:
        return {'status': 'no-op', 'fork': fork, 'incoming': incoming}
    if not output('diff', '--name-only', base, incoming, '--', '.pkgmeta'):
        return {'status': 'unchanged', 'base': base, 'fork': fork, 'incoming': incoming}
    with tempfile.TemporaryDirectory(prefix='eui-pkgmeta-audit-') as temporary:
        temp = Path(temporary)
        env = os.environ.copy()
        objects = temp / 'objects'
        objects.mkdir()
        original = Path(output('rev-parse', '--git-path', 'objects'))
        if not original.is_absolute():
            original = root / original
        env['GIT_OBJECT_DIRECTORY'] = str(objects)
        env['GIT_ALTERNATE_OBJECT_DIRECTORIES'] = str(original.resolve())
        ff = run('merge-base', '--is-ancestor', fork, incoming, allowed=(0, 1)).returncode == 0
        if ff:
            proposed = incoming
        else:
            candidate = run('-c', 'merge.autoStash=false', 'merge-tree', '--write-tree', fork, incoming,
                            env=env, allowed=(0, 1))
            if candidate.returncode:
                raise ValueError('Git reports a conflict in the proposed integration; human choice required.\n' +
                                 candidate.stdout.decode('utf-8', 'replace'))
            proposed = candidate.stdout.decode('ascii').splitlines()[0]
            if not re.fullmatch(r'[0-9a-f]{40,64}', proposed):
                raise ValueError('Unexpected merge-tree output')
        refs = {'base': base, 'fork': fork, 'incoming': incoming, 'proposed': proposed}
        texts = {key: run('show', ref + ':.pkgmeta', env=env).stdout.decode('utf-8') for key, ref in refs.items()}
        bundle = temp / 'versions.json'
        bundle.write_text(json.dumps(texts), encoding='utf-8')
        parser = root / '.tools/install/read-pkgmeta.ps1'
        versions = json.loads(command([powershell, '-NoProfile', '-ExecutionPolicy', 'Bypass',
                                       '-File', str(parser), '-InputPath', str(bundle)], root).stdout)
        files = {key: output('ls-tree', '-r', '--name-only', ref, env=env).splitlines()
                 for key, ref in refs.items()}
        policy_name = '.tools/toc_policy.json'
        if policy_name not in files['fork']:
            raise ValueError('Previous fork must provide the central TOC policy')
        if policy_name not in files['proposed']:
            raise ValueError('Proposed snapshot must preserve the central TOC policy')
        classifications, policy_sources = {}, {}
        for key, ref in refs.items():
            # Upstream may predate or not carry this fork's maintained policy.
            # Reuse explicit fork classifications only; unknown paths still fail.
            policy_ref = ref if policy_name in files[key] else fork
            policy_sources[key] = key if policy_ref == ref else 'fork (policy absent in this version)'
            policy_file = temp / (key + '-toc-policy.json')
            policy_file.write_bytes(run('show', policy_ref + ':' + policy_name, env=env).stdout)
            _, classifications[key] = tocs.load_policy(policy_file)
        paths = {key: suite_manifests(files[key], classifications[key]) for key in refs}
        proposed_tocs = {p for p in files['proposed'] if p.lower().endswith('.toc')}
        missing = classifications['proposed'].keys() - proposed_tocs
        if missing:
            raise ValueError('Missing classified proposed manifests: ' + ', '.join(sorted(missing)))
        validate_layout(versions['proposed'], files['proposed'], classifications['proposed'])
        history = output('log', '--format=commit %H', '-p', base + '..' + fork, '--', '.pkgmeta')
        removed = set(versions['base']['ignore']) - set(versions['incoming']['ignore'])
        touched = [rule for rule in removed if any(re.fullmatch(r'[+-]\s+-\s+' + re.escape(rule), line)
                                                  for line in history.splitlines())]
        fork_changes = output('diff', '--name-only', base, fork, '--').splitlines()
        report = compare(versions, paths, retained, touched, fork_changes)
        report.update(status='decision-required' if report['risks'] else 'safe', refs=refs, fast_forward=ff)
        report['policy_sources'] = policy_sources
        report['textual_diffs'] = {
            label: ''.join(difflib.unified_diff(texts[left].splitlines(keepends=True),
                                              texts[right].splitlines(keepends=True),
                                              fromfile=left + '/.pkgmeta', tofile=right + '/.pkgmeta'))
            for label, left, right in [('incoming', 'base', 'incoming'), ('proposed', 'fork', 'proposed')]}
        report['proposed_pkgmeta_sha256'] = content_digest(texts['proposed'].encode('utf-8'))
        return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--git', help='Validated absolute native Git executable')
    parser.add_argument('--powershell', default=r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe')
    parser.add_argument('--destination')
    parser.add_argument('--source', help='Frozen eligible release SHA, Retail ref, or fetched origin ref')
    parser.add_argument('--report', type=Path, help='New report file outside the checkout')
    parser.add_argument('--verify-report', type=Path, help='Check integrated .pkgmeta against the audited candidate')
    parser.add_argument('--retain-ignore', action='append', default=[])
    args = parser.parse_args()
    try:
        if args.verify_report:
            report = json.loads(args.verify_report.read_text(encoding='utf-8-sig'))
            expected = report.get('proposed_pkgmeta_sha256')
            if not expected or content_digest((args.root / '.pkgmeta').read_bytes()) != expected:
                raise ValueError('Integrated .pkgmeta differs from the audited candidate; renewed review required')
            print('Integrated .pkgmeta matches the audited candidate')
            return 0
        if not args.git or not args.destination or not args.source:
            raise ValueError('--git, --destination and --source are required for an audit')
        if not Path(args.git).is_absolute() or not Path(args.git).is_file():
            raise ValueError('Native Git must be an existing absolute path')
        report = audit(args.root.resolve(), args.git, args.powershell, args.destination, args.source, args.retain_ignore)
        text = json.dumps(report, indent=2)
        if args.report:
            if args.report.resolve().is_relative_to(args.root.resolve()):
                raise ValueError('Audit reports must be outside the checkout')
            with args.report.open('x', encoding='utf-8') as stream:
                stream.write(text + '\n')
        print(text)
        return 3 if report['status'] == 'decision-required' else 0
    except (ValueError, OSError, KeyError) as exc:
        print('ERROR ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
