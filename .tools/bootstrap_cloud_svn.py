#!/usr/bin/env python3
"""Prepare a private SVN runtime for Debian Codex Cloud; never install globally."""
import argparse
import ipaddress
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.parse import urlsplit

PREFIX = Path('/home/agent/.local/eui-svn')


def proxy_args(environ):
    proxy = (environ.get('HTTPS_PROXY') or environ.get('https_proxy')
             or environ.get('HTTP_PROXY') or environ.get('http_proxy'))
    if not proxy:
        return []
    error = 'Invalid SVN proxy URL: expected http://host[:port] without credentials, path, query or fragment'
    try:
        parsed = urlsplit(proxy)
        host = parsed.hostname
        port = parsed.port
        if (parsed.scheme != 'http' or not host or '@' in parsed.netloc
                or parsed.path or '?' in proxy or '#' in proxy or '\\' in proxy
                or any(character.isspace() or ord(character) < 32 for character in proxy)
                or parsed.netloc.endswith(':') or (port is not None and not 1 <= port <= 65535)):
            raise ValueError(error)
        if ':' in host:
            ipaddress.IPv6Address(host)
            if parsed.netloc != f'[{host}]' + (f':{port}' if port is not None else ''):
                raise ValueError(error)
        elif ('[' in parsed.netloc or ']' in parsed.netloc or len(host) > 253
              or not all(re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?', label)
                         for label in host.rstrip('.').split('.'))):
            raise ValueError(error)
    except ValueError:
        raise RuntimeError(error) from None
    return ['--config-option', 'servers:global:http-proxy-host=' + host,
            '--config-option', 'servers:global:http-proxy-port=' + str(port if port is not None else 80)]


def svn_command(arguments, environ):
    return [str(PREFIX / 'root/usr/bin/svn'), '--non-interactive', '--no-auth-cache',
            '--config-dir', str(PREFIX / 'config'), *proxy_args(environ), *arguments]


def bootstrap():
    release = dict(line.strip().split('=', 1) for line in Path('/etc/os-release').read_text().splitlines() if '=' in line)
    if release.get('ID', '').strip('"') != 'debian':
        raise RuntimeError('This rootless bootstrap supports Debian Cloud images only')
    suite = release['VERSION_CODENAME'].strip('"')
    for directory in ['apt/lists/partial', 'apt/archives/partial', 'apt/empty', 'root', 'config']:
        (PREFIX / directory).mkdir(parents=True, exist_ok=True)
    sources = PREFIX / 'apt/sources.list'
    sources.write_text(f'deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] https://deb.debian.org/debian {suite} main\n')
    config = PREFIX / 'apt/apt.conf'
    config.write_text(f'''Dir::Etc::parts "{PREFIX}/apt/empty";
Dir::Etc::main "{PREFIX}/apt/empty/main";
Dir::Etc::sourcelist "{sources}";
Dir::Etc::sourceparts "{PREFIX}/apt/empty";
Dir::State::lists "{PREFIX}/apt/lists";
Dir::Cache::archives "{PREFIX}/apt/archives";
Dir::Cache::pkgcache "{PREFIX}/apt/pkgcache.bin";
Dir::Cache::srcpkgcache "{PREFIX}/apt/srcpkgcache.bin";
Dir::Log "{PREFIX}/apt";
APT::Sandbox::User "agent";
Debug::NoLocking "true";
''')
    env = dict(os.environ, APT_CONFIG=str(config))
    for scheme in ['http', 'https']:
        if env.get(scheme.upper() + '_PROXY'):
            env[scheme + '_proxy'] = env[scheme.upper() + '_PROXY']
    subprocess.run(['/usr/bin/apt-get', 'update', '-o', 'APT::Update::Error-Mode=any'], env=env, check=True)
    # Remove only package downloads from our private cache, never system APT files.
    for package in (PREFIX / 'apt/archives').glob('*.deb'):
        package.unlink()
    subprocess.run(['/usr/bin/apt-get', '--download-only', '--no-install-recommends', '-y', 'install', 'subversion'], env=env, check=True)
    # Rebuild only the private extraction tree; never follow a root symlink.
    extraction_root = PREFIX / 'root'
    if extraction_root.is_symlink():
        extraction_root.unlink()
    elif extraction_root.exists():
        shutil.rmtree(extraction_root)
    extraction_root.mkdir()
    for package in sorted((PREFIX / 'apt/archives').glob('*.deb')):
        subprocess.run(['dpkg-deb', '-x', str(package), str(extraction_root)], check=True)
    library_dirs = sorted((PREFIX / 'root/usr/lib').glob('*-linux-gnu'))
    env['LD_LIBRARY_PATH'] = ':'.join(map(str, library_dirs)) + (':' + env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
    subprocess.run([str(PREFIX / 'root/usr/bin/svn'), '--version', '--quiet'], env=env, check=True)
    # Copy only this standalone wrapper; it never depends on the checkout later.
    wrapper = PREFIX / 'wrapper.py'
    wrapper.write_bytes(Path(__file__).read_bytes())
    bindir = PREFIX.parent / 'bin'
    bindir.mkdir(parents=True, exist_ok=True)
    launcher = bindir / 'svn'
    import shlex
    launcher.write_text('#!/bin/sh\nexec ' + shlex.quote(sys.executable) + ' -B ' + shlex.quote(str(wrapper)) + ' --svn "$@"\n')
    launcher.chmod(0o755)
    print('SVN prepared at /home/agent/.local/bin/svn; prepend that directory to PATH.')


def main():
    if sys.argv[1:2] == ['--svn']:
        env = dict(os.environ)
        directories = sorted((PREFIX / 'root/usr/lib').glob('*-linux-gnu'))
        env['LD_LIBRARY_PATH'] = ':'.join(map(str, directories)) + (':' + env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
        return subprocess.call(svn_command(sys.argv[2:], env), env=env)
    argparse.ArgumentParser(description=__doc__).parse_args()
    bootstrap()
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'[error] {error}', file=sys.stderr)
        sys.exit(1)
