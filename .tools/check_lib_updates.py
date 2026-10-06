#!/usr/bin/env python3
"""Check external library versions; vendor only with explicit --apply approval.

Canonical maintenance checker used by the update workflows.
Uses standard-library parsing of the restricted .pkgmeta externals format.
Requires Git and, for WowAce sources, SVN.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
PKGMETA_PATH = '.pkgmeta'
LOCKFILE_PATH = '.pkgmeta-lock.json'
CACHE_DIR = '.pkgmeta-cache'

def parse_externals(pkgmeta_text: str) -> dict:
    lines = pkgmeta_text.splitlines()
    externals = {}
    in_externals = False
    current_path = None
    current = {}

    def flush():
        if current_path is not None:
            externals[current_path] = current.copy()
    for raw_line in lines:
        line = raw_line.rstrip()
        if not line.strip():
            continue
        indent = len(raw_line) - len(raw_line.lstrip(' '))
        stripped = line.strip()
        if in_externals and indent == 0:
            flush()
            in_externals = False
            current_path = None
            current = {}
            continue
        if stripped == 'externals:':
            in_externals = True
            continue
        if not in_externals:
            continue
        if indent <= 2 and stripped.endswith(':') and (':' not in stripped[:-1]):
            flush()
            current_path = stripped[:-1]
            current = {}
            continue
        m = re.match('([\\w-]+):\\s*(.+)', stripped)
        if m and current_path is not None:
            key, value = (m.group(1), m.group(2).strip())
            current[key] = value
    flush()
    return externals

def short_name(path: str) -> str:
    return path.rstrip('/').split('/')[-1]

def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=60, **kwargs)

def latest_git_tag(url: str) -> str | None:
    result = run(['git', 'ls-remote', '--tags', '--sort=-v:refname', url])
    require_success(result, 'Git tag lookup')
    for line in result.stdout.splitlines():
        parts = line.split('refs/tags/')
        if len(parts) == 2:
            tag = parts[1]
            if tag.endswith('^{}'):
                tag = tag[:-3]
            return tag
    return None

def latest_git_commit(url: str, branch: str='HEAD') -> str | None:
    result = run(['git', 'ls-remote', url, branch])
    require_success(result, 'Git commit lookup')
    if not result.stdout.strip():
        return None
    return result.stdout.split()[0]

def declared_git_commit(url: str, tag: str) -> str | None:
    result = run(['git', 'ls-remote', url, f'refs/tags/{tag}', f'refs/tags/{tag}^{{}}'])
    require_success(result, 'Git declared tag lookup')
    refs = {ref: commit for line in result.stdout.splitlines() if len(line.split()) == 2
            for commit, ref in [line.split()]}
    return refs.get(f'refs/tags/{tag}^{{}}') or refs.get(f'refs/tags/{tag}')

def local_version(text: str) -> tuple[str, str] | None:
    version = re.search(r'local\s+_VERSION\s*=\s*"([^"]+)"', text)
    if version:
        return ('release', version.group(1))
    minor = re.search(r'NewLibrary\("[^"]+",\s*(\d+)\)', text)
    if not minor:
        minor = re.search(r'(?:LIBSTUB_MINOR|MAJOR, MINOR)\s*=\s*"[^"]+",\s*(\d+)', text)
    return ('minor', minor.group(1)) if minor else None

def relevant_files(directory: Path) -> dict[str, bytes]:
    """Compare all EUI library runtime sources and loading manifests byte for byte."""
    files = {}
    for source in directory.rglob('*'):
        if source.suffix.lower() not in {'.lua', '.xml', '.toc'}:
            continue
        if source.is_symlink() or any(parent.is_symlink() for parent in source.parents):
            raise RuntimeError('Cannot prove equivalence of symbolic links')
        if source.is_file():
            files[source.relative_to(directory).as_posix()] = source.read_bytes()
    if not files:
        raise RuntimeError('No relevant library content to compare')
    return files

def upstream_files(entry: dict, resolved: tuple[str, str]) -> dict[str, bytes]:
    """Read an exact upstream snapshot in temporary storage, never into the addon."""
    kind, version = resolved
    url = entry.get('url', '')
    with tempfile.TemporaryDirectory(prefix='eui-library-compare-') as temporary:
        snapshot = Path(temporary) / 'snapshot'
        if kind == 'svn-rev':
            result = run(['svn', 'export', '-r', version, url, str(snapshot)])
            require_success(result, 'SVN snapshot comparison')
            return relevant_files(snapshot)
        repo_url, _, subpath = url.partition('.git/')
        commit = declared_git_commit(repo_url, version) if kind == 'git-tag' else version
        if not commit or not re.fullmatch(r'[0-9a-f]{40}', commit):
            raise RuntimeError('Could not resolve an exact upstream Git snapshot')
        require_success(run(['git', 'init', '--bare', str(snapshot)]), 'Git comparison initialization')
        require_success(run(['git', '-C', str(snapshot), 'fetch', '--depth=1', '--no-tags', repo_url, commit]), 'Git snapshot comparison')
        tree = run(['git', '-C', str(snapshot), 'ls-tree', '-r', '-z', commit])
        require_success(tree, 'Git snapshot manifest lookup')
        files = {}
        prefix = subpath.rstrip('/') + '/' if subpath else ''
        for line in filter(None, tree.stdout.split('\0')):
            metadata, filename = line.split('\t', 1)
            if not filename.startswith(prefix) or Path(filename).suffix.lower() not in {'.lua', '.xml', '.toc'}:
                continue
            mode, object_type, blob = metadata.split()
            if mode not in {'100644', '100755'} or object_type != 'blob':
                raise RuntimeError('Cannot prove equivalence of non-regular Git files')
            content = subprocess.run(['git', '-C', str(snapshot), 'cat-file', 'blob', blob],
                                     capture_output=True, timeout=60)
            require_success(content, 'Git snapshot content lookup')
            files[filename[len(prefix):]] = content.stdout
        if not files:
            raise RuntimeError('No relevant upstream library content to compare')
        return files

def baseline_without_lock(path: str, entry: dict, resolved: tuple[str, str]):
    """Return comparable old/new versions; absence of evidence is UNKNOWN."""
    kind, upstream = resolved
    tag = entry.get('tag')
    url = entry.get('url', '')
    if kind == 'git-commit' and tag and tag.lower() not in {'latest', 'alpha', 'beta', 'head'}:
        baseline = declared_git_commit(url.split('.git/')[0], tag)
        if not baseline:
            raise RuntimeError(f'Could not resolve declared tag {tag}')
        return baseline, upstream
    local_files = relevant_files(Path(path))
    remote_files = upstream_files(entry, resolved)
    if local_files == remote_files:
        return upstream, upstream
    filename = short_name(path) + '.lua'
    local = local_version(local_files.get(filename, b'').decode('utf-8'))
    remote = local_version(remote_files.get(filename, b'').decode('utf-8'))
    if not local or not remote or local[0] != remote[0]:
        raise RuntimeError('Upstream and local version markers are not comparable')
    if local[0] == 'minor' and int(remote[1]) > int(local[1]):
        return local[1], remote[1]
    if local[0] == 'release':
        old = re.fullmatch(r'(\d+)\.(\d+)\.(\d+)-release', local[1])
        new = re.fullmatch(r'(\d+)\.(\d+)\.(\d+)-release', remote[1])
        if old and new and tuple(map(int, new.groups())) > tuple(map(int, old.groups())):
            return local[1], remote[1]
    raise RuntimeError('Content differs without a proven version advance; equivalence is UNKNOWN')

def latest_svn_revision(url: str) -> str | None:
    result = run(['svn', 'info', '--xml', url])
    require_success(result, 'SVN revision lookup')
    try:
        root = ET.fromstring(result.stdout)
    except ET.ParseError:
        return None
    commit = root.find('.//entry/commit')
    if commit is None:
        return None
    return commit.get('revision')

def resolve_upstream_version(entry: dict) -> tuple[str, str] | None:
    url = entry.get('url', '')
    tag = entry.get('tag')
    if 'repos.wowace.com' in url:
        rev = latest_svn_revision(url)
        return ('svn-rev', rev) if rev else None
    clean_url = url.split('.git/')[0]
    if not clean_url.endswith('.git'):
        clean_url = clean_url
    if tag == 'latest':
        t = latest_git_tag(clean_url)
        return ('git-tag', t) if t else None
    else:
        c = latest_git_commit(clean_url)
        return ('git-commit', c) if c else None

def load_lockfile() -> dict:
    if os.path.exists(LOCKFILE_PATH):
        with open(LOCKFILE_PATH, 'r', encoding='utf-8') as f:
            return json.load(f)
    return {}

def save_lockfile(data: dict) -> None:
    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8',
                                         dir=os.path.dirname(os.path.abspath(LOCKFILE_PATH)),
                                         delete=False) as f:
            temporary_path = f.name
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write('\n')
        os.replace(temporary_path, LOCKFILE_PATH)
    finally:
        if temporary_path and os.path.exists(temporary_path):
            os.remove(temporary_path)

def main():
    try:
        return check_updates()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'[error] {error}', file=sys.stderr)
        return 1

def check_updates():
    parser = argparse.ArgumentParser(description='Check updates for .pkgmeta external libraries')
    parser.add_argument('--apply', metavar='NAME', help="Short library name to vendor (or 'all' for all pending updates). Without this flag, only report.")
    args = parser.parse_args()
    if not os.path.exists(PKGMETA_PATH):
        print(f'Could not find {PKGMETA_PATH} on the current branch.', file=sys.stderr)
        sys.exit(1)
    branch = run(['git', 'rev-parse', '--abbrev-ref', 'HEAD']).stdout.strip() or '?'
    with open(PKGMETA_PATH, 'r', encoding='utf-8') as f:
        pkgmeta_text = f.read()
    externals = parse_externals(pkgmeta_text)
    lock = load_lockfile()
    pending = {}
    current = 0
    unresolved = 0
    for path, entry in externals.items():
        name = short_name(path)
        try:
            resolved = resolve_upstream_version(entry)
            if resolved is None:
                raise RuntimeError('Could not resolve upstream version')
            kind, upstream_version = resolved
            locked = lock.get(path, {})
            locked_version = locked.get('value')
            old, new = (locked_version, upstream_version) if locked_version is not None else baseline_without_lock(path, entry, resolved)
        except (OSError, RuntimeError, subprocess.SubprocessError, ValueError) as error:
            unresolved += 1
            print(f'[?] UNKNOWN {name} ({path}) - {error} (url: {entry.get("url")})')
            continue
        if old == new:
            current += 1
            print(f'    {name}: current={old}; upstream={upstream_version}')
            continue
        pending[path] = {'name': name, 'entry': entry, 'kind': kind, 'old': old, 'new': upstream_version}
        old_display = old
        print(f'[!] {name}: update available')
        print(f'    current: {old_display}')
        print(f'    new    : {upstream_version}')
        if new != upstream_version:
            print(f'    upstream local-version marker: {new}')
    print(f'Libraries | branch={branch} | CHECKED={len(externals)} | current={current} | pending={len(pending)} | UNKNOWN={unresolved} | unresolved={unresolved}')
    if unresolved:
        print('Library check incomplete; unresolved sources are not confirmed current.', file=sys.stderr)
        return 1
    if not pending:
        return 0
    if not args.apply:
        print('\nAfter approval, run --apply <name> (or --apply all) to vendor the listed libraries on this branch.')
        return
    targets = list(pending.keys()) if args.apply == 'all' else [p for p, info in pending.items() if info['name'] == args.apply]
    if not targets:
        print(f"\nNo pending library named '{args.apply}'.", file=sys.stderr)
        sys.exit(1)
    for path in targets:
        info = pending[path]
        vendor_lib(path, info)
    # Publish version records only after every requested vendoring succeeds.
    for path in targets:
        info = pending[path]
        lock[path] = {'kind': info['kind'], 'value': info['new']}
    save_lockfile(lock)
    for path in targets:
        info = pending[path]
        print(f"{info['name']} updated to {info['new']} into {path}")
    print(f'\n{LOCKFILE_PATH} updated. Review `git diff` before committing.')
    return 0

def require_success(result, operation):
    if result.returncode != 0:
        raise RuntimeError(f'{operation} failed ({result.returncode}): {result.stderr.strip()}')

def vendor_lib(path: str, info: dict) -> None:
    entry = info['entry']
    url = entry.get('url', '')
    name = info['name']
    print(f'\nVendoring {name} into {path}')
    with tempfile.TemporaryDirectory() as tmp:
        if 'repos.wowace.com' in url:
            result = run(['svn', 'export', '--force', '-r', info['new'], url, tmp])
            require_success(result, f'SVN export for {name}')
        else:
            clean_url, _, subpath = url.partition('.git/')
            if not clean_url.endswith('.git'):
                pass
            clone_dir = os.path.join(tmp, '_clone')
            ref_args = []
            if info['kind'] == 'git-tag':
                ref_args = ['--branch', info['new']]
            result = run(['git', 'clone', '--depth', '1', *ref_args, clean_url, clone_dir])
            if result.returncode != 0 and info['kind'] == 'git-tag':
                if os.path.exists(clone_dir):
                    shutil.rmtree(clone_dir)
                result = run(['git', 'clone', clean_url, clone_dir])
                require_success(result, f'Git clone for {name}')
                result = run(['git', 'checkout', info['new']], cwd=clone_dir)
                require_success(result, f'Git checkout for {name}')
            require_success(result, f'Git clone for {name}')
            if info['kind'] == 'git-commit':
                result = run(['git', 'checkout', info['new']], cwd=clone_dir)
                require_success(result, f'Git checkout for {name}')
            src = clone_dir
            if subpath:
                src = os.path.join(clone_dir, subpath)
            shutil.rmtree(os.path.join(tmp, 'export'), ignore_errors=True)
            shutil.copytree(src, os.path.join(tmp, 'export'), ignore=shutil.ignore_patterns('.git'))
            tmp = os.path.join(tmp, 'export')
        os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
        if os.path.exists(path):
            shutil.rmtree(path)
        shutil.copytree(tmp, path)
    cache_path = os.path.join(CACHE_DIR, name, info['new'])
    if not os.path.exists(cache_path):
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        shutil.copytree(path, cache_path)
if __name__ == '__main__':
    sys.exit(main())
