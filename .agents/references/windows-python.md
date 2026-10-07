# Windows interpreter discovery

Load only when Windows launchers cannot start the resolver. Use the frozen
platform and repository context from [maintenance preflight](python-runtime.md).

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
executable in the shared context. A resolver failure remains a workflow failure; discovery
only repairs a launcher that cannot start it. The resolver already probes the
bootstrap interpreter as a fallback and validates all helper entry points.
