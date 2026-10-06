# Rootless SVN for Codex Cloud

The canonical EUI Cloud preparation entry point is [Python runtime](python-runtime.md).
There is no versioned Cloud environment configuration. In the existing environment's
setup script, resolve Python once, then run:

```sh
<python_runtime> -B .tools/bootstrap_cloud_svn.py
export PATH="/home/agent/.local/bin:$PATH"
svn --version --quiet
```

Replace `<python_runtime>` with the absolute path returned by the preflight.
Ensure `/home/agent/.local/bin` is on PATH for subsequent tasks as well.
The bootstrap supports Debian images with `/usr/bin/apt-get`, `dpkg-deb`, and
the Debian archive keyring. It refreshes private, signature-verified package
indexes, downloads SVN and dependencies, and extracts packages without running
package installation scripts. All writes stay under `/home/agent/.local`.
It uses no sudo, global installation, repository cache, or addon mutation.

The wrapper supplies the inherited HTTPS_PROXY/HTTP_PROXY (including lowercase
variants) explicitly through SVN's `--config-option` proxy host and port.
It supports an HTTP proxy for HTTPS destinations, preserves TLS verification,
uses noninteractive operation and `--no-auth-cache`, and does not persist proxy
credentials. Proxies containing credentials or unsupported schemes fail clearly.
APT and Python HTTP lookups retain the inherited HTTP/HTTPS proxy route.

Cloud network policy must allow `deb.debian.org`, `repos.wowace.com`,
`github.com`, and `raw.githubusercontent.com`. A policy rejection is an error;
do not bypass the proxy or claim the corresponding library is current.
Setup success proves SVN availability, not access to every source.

Normal checks never install tools automatically. Prepare this runtime in the
environment setup, or as a separately authorized environment bootstrap. Run
`.tools/check_lib_updates.py` without apply arguments to validate all sources.
This setup does not change release cutoff, branch routing, or addon installation.
