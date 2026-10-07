# Shared maintenance context and Python preflight

Initialize root and environment once at maintenance entry. Reuse the context
when entering another skill or branch; runtime and optional capabilities remain
unresolved until their first required use.

- Freeze `repo_root` from `git rev-parse --show-toplevel`; compare it with the
  requested repository and stop on mismatch. Reuse an already verified result.
- Freeze `environment` from trusted session/host metadata: `local_windows` for
  confirmed local Windows execution, `cloud` only when the session or host
  explicitly identifies Codex Cloud. Linux alone, a branch named `work`, paths,
  or missing WoW folders are not proof of Cloud. Use `other` if neither is proven;
  ask only if an environment-specific action depends on the distinction.
- Resolve and freeze `python_runtime` below only before the first mutation or
  first helper requiring Python, whichever comes first. PR metadata, changed
  paths, and read-only analysis without Python helpers must not wait for it.
- Determine and cache `physical_install` only at the install stage when needed:
  unavailable in Cloud or other nonlocal execution.
  In local Windows, establish access to the existing operational script directory
  and mode-relevant WoW folders from trusted host evidence or a minimal read-only
  existence/access check. Do not load physical install commands before approval.
  Record unavailable if access cannot be established; sync may still continue,
  and the unchanged install menu remains mandatory.
- Discover and cache environment fallbacks only when first needed
  (Windows interpreter discovery only on Windows; prepared rootless SVN only in
  confirmed Cloud). Discovery is not authorization to install or bootstrap tools.
  Probe an optional capability only when first needed, cache its result, and do
  not load unrelated environment references.

Retain these values in agent context, not a new tracked configuration file.
Checkout cannot change the host, root, or interpreter. Do not repeat discovery
between stages; stop on an invalidated pinned capability rather than silently
switching environments or runtimes. Batch independent read-only facts and report
healthy results in aggregate; keep errors and human choices visible.

## Python resolution

Resolve Python 3 once immediately before the first mutation or Python helper,
whichever comes first. This includes stash, checkout/switch, branch creation/reset,
merge, commit, push, or addon installation. Read-only Git checks, fetch, and PR
analysis without Python helpers may precede resolution. Do not install Python
automatically. Once resolved, reuse the same runtime across all skills and branches.

Bootstrap the resolver with the first runnable command for the known platform:

| Platform | Bootstrap attempts, in order |
| --- | --- |
| Windows | `py -3 .tools/python_runtime.py`, `python .tools/python_runtime.py`, `python3 .tools/python_runtime.py` |
| Non-Windows | `python3 .tools/python_runtime.py`, `python .tools/python_runtime.py` |

Bootstrap only loads the resolver; `.tools/python_runtime.py` owns candidate
ordering, real version checks, timeouts, and helper compatibility checks. It
rejects Python 2, tests helpers with `--help` without running their operations,
and returns compact JSON containing an absolute `python` path and `version`.
Stop at the first successful result. If a running Python 3 resolver reports
failure, stop; retrying cannot help. Only when Windows launchers cannot start it,
read [Windows interpreter discovery](windows-python.md). Never load that fallback
on another platform.

If resolution fails, briefly report in Portuguese that maintenance requires
Python 3. Preserve edits and stop before branch mutation or installation.
Freeze the returned absolute path as `python_runtime` for every helper, optional
library stage, and Both branch. If it becomes unavailable, stop instead of
selecting another. `<python_runtime>` denotes this path, not a literal command.

For spaces, use `& '<python_runtime>' .tools/release_target.py` in PowerShell or
`'<python_runtime>' .tools/release_target.py` in Bash. Shell variables may not
survive tool calls; retain the path in agent context and pass it explicitly.

## Dependencies on demand

The maintenance Python helpers use only the standard library; no pip install or
PyYAML is required. The unrelated nameplate test's `lupa` is not an update
dependency. Git is required for sync; accepted library checks may also need SVN
and network access. Check these only at their relevant stage and reuse results.

Only confirmed Cloud setup needs [Cloud preparation](cloud-svn.md).
Normal updates never install tools. At the install checkpoint, load only
`eui-install` for its unchanged menu; physical commands remain local Windows only.
