# Shared Python preflight

Maintenance requires Python 3. Run this preflight once per execution, before stash,
checkout/switch, branch creation/reset, merge, commit, push, or addon installation.
Read-only Git checks and fetch may precede it. Do not install Python automatically.

The workflow is agent-driven, not a shell program. Bootstrap the single resolver
with the first runnable command in this table (skip missing/broken launchers):

| Platform | Bootstrap attempts, in order |
| --- | --- |
| Windows | `py -3 .tools/python_runtime.py`, `python .tools/python_runtime.py`, `python3 .tools/python_runtime.py` |
| Linux / Cloud | `python3 .tools/python_runtime.py`, `python .tools/python_runtime.py` |

Bootstrap only loads the resolver; `.tools/python_runtime.py` owns candidate
ordering, real version checks, timeouts, and helper compatibility checks. It
rejects Python 2, tests the helpers with `--help` without running their operations,
and returns compact JSON containing an absolute `python` path and `version`.
Stop bootstrap attempts on the first successful resolver result. If a running
Python 3 resolver reports failure, stop the workflow; retrying cannot help.
If none of the normal launchers can start the resolver on Windows, discover
existing interpreters before declaring Python unavailable. Do not change PATH,
install Python, or retry after a running Python 3 resolver reports failure.
Inspect `Get-Command` and `where.exe` results first: a WindowsApps alias may hide
a real executable later in PATH. Then inspect trusted local installation roots:
`<user profile>\AppData\Local\Programs\Python\Python*\python.exe`,
`<user profile>\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe`,
and Python installation paths registered under HKCU/HKLM `Software\Python`.
Use the actual user profile (for example, `$env:USERPROFILE`), not only
`$env:LOCALAPPDATA`, which a sandbox may redirect. Discover installed versions;
do not assume a particular version or username. Skip WindowsApps aliases,
missing executables, and untrusted repository or working-directory candidates.
For each existing trusted candidate, use PowerShell's call operator:
`& '<absolute executable>' --version`, then
`& '<absolute executable>' .tools/python_runtime.py` when it reports Python 3.
Stop at the first successful resolver result and freeze its returned absolute
executable as below. A resolver failure remains a workflow failure; discovery
only repairs a launcher that cannot start it. The resolver already probes the
bootstrap interpreter as a fallback and validates all helper entry points.

If no bootstrap runs successfully after this discovery, report briefly in Portuguese that maintenance
tools require Python 3 and stop. Preserve all local edits; do not stash or mutate
branches, merge, commit, push, or install the addon after preflight failure.

Freeze the returned absolute path as `python_runtime` in the execution context.
Use that path for every helper, including the optional library stage and both
branches in Both mode. Do not resolve again after a checkout or helper failure.
If the pinned interpreter becomes unavailable, stop instead of selecting another.
`<python_runtime>` in skills denotes this path, not a literal shell command.

For paths with spaces, invoke `& '<python_runtime>' .tools/release_target.py` in
PowerShell or `'<python_runtime>' .tools/release_target.py` in Bash. Shell variables
do not survive every tool call: retain the path in agent context and pass it
explicitly on subsequent calls. Never require the user to change their commands.

## Dependencies and Cloud setup

`python_runtime.py`, `release_target.py`, `classify_library_range.py`, and
`check_lib_updates.py` use only the Python standard library. No pip install or
PyYAML is required. PyYAML is only relevant to optional generic YAML validation;
the helpers parse the project's restricted `.pkgmeta` externals format directly.
The unrelated nameplate test uses `lupa`; it is not an update dependency.
Git is required for sync; an explicitly accepted library check may also need SVN
and network access to library sources. Keep the existing human checkpoints.

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
Cloud cannot access the local WoW folders or Windows installer. Preserve the
install menu; if installation is chosen there, report that it requires the local
Windows environment and stop without running the Windows commands in Cloud.
