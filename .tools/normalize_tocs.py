"""Validate or normalize explicitly classified manifests without requiring Git."""
import argparse
import codecs
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tempfile

POLICY = Path(__file__).with_name('toc_policy.json')
HEADER = re.compile(rb'^(##[ \t]*)([^:\r\n]+)(:[ \t]*)([^\r\n]*)(\r\n|\n|\r)?$')
KINDS = {'retail', 'camelot', 'shared', 'embedded'}
SKIP_ROOTS = {'.git', '.release', '.pkgmeta-cache'}


def load_policy(path=POLICY):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('Duplicate policy key: ' + key)
            result[key] = value
        return result
    policy = json.loads(Path(path).read_text(encoding='utf-8'), object_pairs_hook=unique)
    if policy.get('schema') != 1 or set(policy['classes']) != KINDS:
        raise ValueError('Unsupported policy schema or manifest classes')
    for value in [*policy['targets'].values(), policy['camelot_interface']]:
        if not isinstance(value, str) or not re.fullmatch(r'[1-9][0-9]*', value):
            raise ValueError('Interfaces must be explicit positive decimal strings')
    classification = {}
    for kind, group in policy['classes'].items():
        if not group['reason']:
            raise ValueError('Each classification needs a loading rationale')
        for name in group['paths']:
            p = PurePosixPath(name)
            if (p.is_absolute() or '..' in p.parts or '\\' in name or ':' in name
                    or str(p) != name or p.suffix.lower() != '.toc'):
                raise ValueError('Unsafe manifest path: ' + name)
            if name.casefold() in {n.casefold() for n in classification}:
                raise ValueError('Manifest classified more than once: ' + name)
            classification[name] = kind
    return policy, classification


def require_target(policy, target):
    if target not in policy['targets']:
        raise ValueError('Unknown target; explicitly configure it in toc_policy.json: ' + str(target))
    return policy['targets'][target]


def ci_target(event, policy):
    if event.get('pull_request'):
        target = event['pull_request']['base']['ref']
    else:
        ref = event.get('ref', '')
        if not ref.startswith('refs/heads/'):
            raise ValueError('CI requires a pull request base or a branch push')
        target = ref.removeprefix('refs/heads/')
    require_target(policy, target)
    return target


def discover(root):
    found = {}
    for directory, dirs, files in os.walk(root, followlinks=False):
        base = Path(directory)
        if base == root:
            dirs[:] = [d for d in dirs if d not in SKIP_ROOTS]
        for name in dirs + files:
            if (base / name).is_symlink():
                raise ValueError('Symlinks are not supported in manifest trees: ' + str(base / name))
        for name in files:
            if name.lower().endswith('.toc'):
                path = base / name
                found[path.relative_to(root).as_posix()] = path
    return found


def normalize(data, kind, retail, camelot):
    """Return proposed bytes; ambiguous metadata is an error, never a conflict fix."""
    data.decode('utf-8-sig')
    bom = codecs.BOM_UTF8 if data.startswith(codecs.BOM_UTF8) else b''
    lines = data[len(bom):].splitlines(keepends=True)
    headers = {}
    for i, line in enumerate(lines):
        if line.startswith((b'<<<<<<<', b'=======', b'>>>>>>>', b'|||||||')):
            raise ValueError('Unresolved conflict marker; resolve through the human checkpoint')
        match = HEADER.fullmatch(line)
        if not match:
            continue
        key = match[2].strip().lower()
        if key in headers:
            raise ValueError('Duplicate header: ' + key.decode())
        if key.startswith(b'interface-'):
            raise ValueError('Client-specific Interface override needs explicit policy review')
        headers[key] = (i, match)
    if kind == 'embedded':
        return data
    allowed = {'retail': 'standard', 'camelot': 'camelot', 'shared': None}[kind]
    clients = {'standard', 'camelot'} if kind == 'shared' else {allowed}
    if b'excludeloadgametype' in headers:
        value = headers[b'excludeloadgametype'][1][4].decode().lower()
        if clients.intersection(re.split(r'[,\s]+', value.strip())):
            raise ValueError('ExcludeLoadGameType conflicts with the classified clients')
    if kind == 'shared' and b'allowloadgametype' in headers:
        raise ValueError('Shared manifest has AllowLoadGameType; review before removing restrictions')
    interface = {'retail': retail, 'camelot': camelot, 'shared': retail + ', ' + camelot}[kind]
    expected = {'Interface': interface}
    if allowed:
        expected['AllowLoadGameType'] = allowed
    newline = next((m[5] for _, m in headers.values() if m[5]), b'\n')
    missing = []
    for key, value in expected.items():
        entry = headers.get(key.lower().encode())
        if entry:
            i, match = entry
            if match[4] != value.encode():
                lines[i] = match[1] + match[2] + match[3] + value.encode() + (match[5] or b'')
        else:
            missing.append(b'## ' + key.encode() + b': ' + value.encode() + newline)
    return bom + b''.join(missing + lines)


def ensure_resolved(root):
    if not (root / '.git').exists():
        return
    git = shutil.which('git')
    if not git:
        raise ValueError('Git is required to check the index in a Git checkout')
    result = subprocess.run([git, '-C', str(root), 'ls-files', '--unmerged'],
                            capture_output=True, check=True, shell=False)
    if result.stdout:
        raise ValueError('Unmerged index; normalization cannot resolve Git conflicts')


def plan(root, policy, classification, target):
    retail = require_target(policy, target)
    ensure_resolved(root)
    found = discover(root)
    errors, changes = [], []
    for name in sorted(set(found) - set(classification)):
        errors.append(name + ': unknown manifest; classify explicitly in toc_policy.json')
    for name in sorted(set(classification) - set(found)):
        errors.append(name + ': classified manifest is missing')
    for name in sorted(set(found) & set(classification)):
        path = found[name]
        try:
            before = path.read_bytes()
            after = normalize(before, classification[name], retail, policy['camelot_interface'])
            if after != before:
                changes.append((path, before, after))
        except (ValueError, OSError) as exc:
            errors.append(name + ': ' + str(exc))
    return errors, changes


def atomic_write(path, data):
    descriptor, temporary = tempfile.mkstemp(prefix='.' + path.name + '.', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        shutil.copymode(path, temporary)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def run(root, target, mode, policy_path=POLICY):
    root = Path(root).resolve()
    policy, classification = load_policy(policy_path)
    errors, changes = plan(root, policy, classification, target)
    for error in errors:
        print('ERROR ' + error, file=sys.stderr)
    if errors:
        return 1
    for path, before, after in changes:
        if mode == 'fix':
            if path.read_bytes() != before:
                raise ValueError('Manifest changed during normalization: ' + str(path))
            atomic_write(path, after)
        print(('FIXED ' if mode == 'fix' else 'DRIFT ') + path.relative_to(root).as_posix())
    print(f'{target}: {len(classification)} manifests; {len(changes)} ' +
          ('changed' if mode == 'fix' else 'inconsistent'))
    return int(mode == 'check' and bool(changes))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['fix', 'check'])
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--policy', type=Path, default=POLICY)
    selection = parser.add_mutually_exclusive_group(required=True)
    selection.add_argument('--target', help='Exact destination branch, even in detached HEAD')
    selection.add_argument('--github-event', type=Path, help='GitHub event JSON (check only)')
    args = parser.parse_args()
    try:
        if args.github_event:
            if args.mode != 'check':
                raise ValueError('GitHub Actions may only check manifests')
            policy, _ = load_policy(args.policy)
            args.target = ci_target(json.loads(args.github_event.read_text(encoding='utf-8')), policy)
        return run(args.root, args.target, args.mode, args.policy)
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as exc:
        print('ERROR ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
