# Cloud preparation and rootless SVN

Read only for confirmed Cloud setup, not routine Windows maintenance. Reuse the
frozen [maintenance context](python-runtime.md); setup is separate from addon
updates and does not change release selection or human checkpoints.

There is no versioned Cloud environment configuration in this repository.
Do not invent one or install tools from `update`. This local chat cannot verify
or publish a remote Cloud environment. In Settings > Codex Cloud > Environments,
edit the project's existing environment and ask setup to verify Python 3 and run
`python3 .tools/python_runtime.py` (or `python .tools/python_runtime.py`). A
successful result needs no Python installation, pip dependencies, or republishing
solely for Python. If missing, request Python 3.12 in the reusable environment
setup, test the preflight, and save and Publish/Republish before starting a new
Cloud task. On the current Cloud UI this is the Install script/setup conversation;
on legacy Cloud environments it is the Setup script/package version setting.

Exact verification-only setup content when `python3` is available:

```sh
python3 .tools/python_runtime.py
```

For a Debian/Ubuntu environment verified to lack Python 3, the reusable Install
script (legacy: Setup script) can prepare the system once:

```sh
sudo apt-get update -qq
sudo apt-get install -y python3
python3 .tools/python_runtime.py
```

Use environment setup to select Python 3.12 if the system package is incompatible.
Do not apply this installation to an environment that already passes preflight.

## Rootless SVN

In the existing environment's setup script, reuse the resolved Python and run:

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
