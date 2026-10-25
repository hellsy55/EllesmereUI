"""Release target, archive validation and a fail-closed adapter for the pinned packager."""
import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import zipfile

import normalize_tocs as tocs
from check_lib_updates import parse_externals, package_ignores

PACKAGER_REF = 'e50a250f8705041e40f2fa1ddcb280a686d65aa0'
PACKAGER_SHA256 = '59b15a8d851b09e6d0fdec702aec91331b9b49d84dbe778da6c621b48f268703'
BOUNDARY = b'###\n### Deploy the zipfile.\n###\n'
GATE = b'''# Validate the actual archives before any publisher is reachable.
if [ -n "${EUI_RELEASE_TAG:-}" ] && [ "$tag" != "$EUI_RELEASE_TAG" ]; then
    echo "Packager selected a different tag than the validated release tag" >&2
    exit 1
fi
"$EUI_PYTHON" -B "$EUI_ROOT/.tools/release_manifest.py" archive --root "$EUI_ROOT" --target "$EUI_TARGET" "$archive" || exit 1
if [ -n "$nolib_archive" ] && [ -f "$nolib_archive" ]; then
    "$EUI_PYTHON" -B "$EUI_ROOT/.tools/release_manifest.py" archive --root "$EUI_ROOT" --target "$EUI_TARGET" "$nolib_archive" || exit 1
fi
'''


def git(root, *args):
    executable = shutil.which('git')
    if not executable:
        raise ValueError('Native Git is required')
    result = subprocess.run([executable, '-C', str(root), *args], shell=False, capture_output=True)
    if result.returncode:
        raise ValueError(f'Git {args[0]} failed ({result.returncode}): ' + result.stderr.decode(errors='replace'))
    return result.stdout.decode('utf-8').strip()


def check_source(root, target):
    policy, classification = tocs.load_policy()
    errors, changes = tocs.plan(root, policy, classification, target)
    if errors or changes:
        raise ValueError('\n'.join(errors + ['TOC drift: ' + p.relative_to(root).as_posix() for p, _, _ in changes]))
    return policy, classification


def clean_checkout(root):
    if git(root, 'status', '--porcelain=v1', '--untracked-files=all'):
        raise ValueError('Release tagging/publication requires a clean checkout')


def tag_target(root, name, remote=False):
    ref = 'refs/tags/' + name
    git(root, 'check-ref-format', ref)
    if git(root, 'cat-file', '-t', ref) != 'tag':
        raise ValueError('Release requires an annotated tag with EUI-Target')
    annotation = git(root, 'cat-file', 'tag', ref).partition('\n\n')[2]
    lines = [line for line in annotation.splitlines() if line.startswith('EUI-Target:')]
    if len(lines) != 1:
        raise ValueError('Tag must contain exactly one EUI-Target: <branch> line')
    target = lines[0].removeprefix('EUI-Target:').strip()
    policy, _ = tocs.load_policy()
    tocs.require_target(policy, target)
    commit = git(root, 'rev-parse', '--verify', ref + '^{commit}')
    if commit != git(root, 'rev-parse', 'HEAD'):
        raise ValueError('Tag commit differs from the checkout being validated')
    branch = ('refs/remotes/origin/' if remote else 'refs/heads/') + target
    tip = git(root, 'rev-parse', '--verify', branch + '^{commit}')
    git(root, 'merge-base', '--is-ancestor', commit, tip)
    clean_checkout(root)
    check_source(root, target)
    return target


def prepare_tag(root, target, name, create=False):
    tocs.require_target(tocs.load_policy()[0], target)
    git(root, 'check-ref-format', 'refs/tags/' + name)
    if git(root, 'symbolic-ref', '--short', 'HEAD') != target:
        raise ValueError('Create the release tag on the declared destination branch')
    clean_checkout(root)
    check_source(root, target)
    commit = git(root, 'rev-parse', 'HEAD')
    if git(root, 'tag', '--list', name):
        raise ValueError('Tag already exists; never replace a release tag')
    if create:
        git(root, 'tag', '-a', name, '-m', f'Release {name}\n\nEUI-Target: {target}', commit)
    return f'{"Created" if create else "Validated (dry run)"}: {name} -> {commit}; EUI-Target: {target}'


def package_layout(root):
    text = (root / '.pkgmeta').read_text(encoding='utf-8')
    ignores = package_ignores(text)
    external_roots = list(parse_externals(text))
    package = re.findall(r'^package-as: ([A-Za-z0-9_-]+)$', text, re.M)
    if len(package) != 1:
        raise ValueError('Unsupported package-as declaration')
    moves, active = {}, False
    for line in text.splitlines():
        if line and not line.startswith((' ', '#')):
            active = line == 'move-folders:'
        elif active and line.strip() and not line.lstrip().startswith('#'):
            match = re.fullmatch(r'  ([A-Za-z0-9_/-]+): ([A-Za-z0-9_/-]+)', line)
            if not match or match[1] in moves:
                raise ValueError('Unsupported or duplicate move-folders declaration')
            moves[match[1]] = match[2]

    def mapped(path):
        if any(path == p or path.startswith(p.rstrip('/') + '/') for p in ignores):
            return None
        result = package[0] + '/' + path
        matches = [src for src in moves if result.startswith(src + '/')]
        if len(matches) > 1:
            raise ValueError('Overlapping move-folders require explicit layout review')
        if matches:
            src = matches[0]
            result = moves[src] + result[len(src):]
        return result
    return mapped, [mapped(p) for p in external_roots if mapped(p)]


def check_archive(root, target, archive):
    policy, classification = check_source(root, target)
    mapped, externals = package_layout(root)
    expected = {mapped(p): (p, kind) for p, kind in classification.items() if mapped(p)}
    errors, seen, external_count = [], set(), 0
    with zipfile.ZipFile(archive) as package:
        names = [i.filename for i in package.infolist()]
        if len({n.casefold() for n in names}) != len(names):
            raise ValueError('Archive contains duplicate paths')
        for name in names:
            path = PurePosixPath(name)
            if path.is_absolute() or '..' in path.parts or '\\' in name:
                raise ValueError('Unsafe archive path: ' + name)
            if not name.lower().endswith('.toc'):
                continue
            if any(name.startswith(p + '/') for p in externals):
                external_count += 1
                continue
            if name not in expected:
                errors.append('Unclassified or excluded packaged manifest: ' + name)
                continue
            source, kind = expected[name]
            seen.add(name)
            data = package.read(name)
            if data != tocs.normalize(data, kind, policy['targets'][target], policy['camelot_interface']):
                errors.append('Packaged TOC drift: ' + name)
            # Packaging may substitute the version and change BOM/newlines only.
            def payload(value):
                return [line for line in value.decode('utf-8-sig').splitlines()
                        if not line.lower().startswith('## version:')]
            if kind != 'embedded' and payload(data) != payload((root / source).read_bytes()):
                errors.append('Packager changed manifest content: ' + name)
        for name, (_, kind) in expected.items():
            if kind != 'embedded' and name not in seen:
                errors.append('Missing packaged manifest: ' + name)
    if errors:
        raise ValueError('\n'.join(errors))
    print(f'Archive validated: {archive}; {len(seen)} suite/embedded manifests; '
          f'{external_count} external manifests excluded from compatibility validation')


def protect_packager(data):
    if hashlib.sha256(data).hexdigest() != PACKAGER_SHA256:
        raise ValueError('Packager checksum differs; review the pinned adapter before packaging')
    if data.count(BOUNDARY) != 1:
        raise ValueError('Packager publication boundary is missing or ambiguous')
    return data.replace(BOUNDARY, GATE + BOUNDARY)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['preflight', 'tag', 'archive', 'protect'])
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--target')
    parser.add_argument('--tag')
    parser.add_argument('--remote', action='store_true', help='Validate tag ancestry against origin')
    parser.add_argument('--create', action='store_true', help='Create the validated local annotated tag; never push')
    parser.add_argument('--output', type=Path)
    parser.add_argument('file', nargs='?')
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        if args.mode == 'protect':
            args.output.write_bytes(protect_packager(Path(args.file).read_bytes()))
        elif args.mode == 'archive':
            check_archive(root, args.target, args.file)
        elif args.mode == 'tag':
            if not args.tag:
                raise ValueError('tag requires --tag and --target')
            print(prepare_tag(root, args.target, args.tag, args.create))
        elif args.tag:
            target = tag_target(root, args.tag, args.remote)
            if args.target and args.target != target:
                raise ValueError('Explicit target disagrees with the annotated tag')
            print(target)
        else:
            target = args.target or git(root, 'symbolic-ref', '--short', 'HEAD')
            check_source(root, target)
            print(target)
    except (ValueError, OSError, KeyError, TypeError, AttributeError, RuntimeError, zipfile.BadZipFile) as exc:
        print('ERROR ' + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
