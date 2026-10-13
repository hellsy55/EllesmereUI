# Shared maintenance context and runtime preflight

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
- Resolve and freeze `lua_runtime` only for work that will create a commit,
  before its first mutation. Read-only checks, no-op updates, fast-forward-only
  syncs and installation without a new commit skip compiler discovery.
  Reuse the descriptor across skills and branches; see Lua compiler resolution.
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

## Lua compiler resolution

Run `<python_runtime> -B .tools/lua_runtime.py --resolve` after read-only scope
and ancestry checks show that work needs a new commit, before its first mutation.
This includes an approved PR application, a merge that needs a commit, direct
maintenance/code changes and approved library vendoring before `--apply`.
Skip this for read-only work, no-op/fast-forward-only updates and
installation from already validated, committed files.

Freeze the JSON descriptor as `lua_runtime` (`mode`, absolute `compiler`,
`version`, `command`) and reuse it across skills and branches. Set `LUAC` to
the frozen native compiler, or `LUA51_DLL` to the frozen DLL with `LUAC` unset,
for the current process/invocation only. Run guardrails with the frozen Python.
Revalidate that exact capability; do not repeat discovery or change compilers.

The resolver honors explicit `LUAC`/`LUA51_DLL` first, then checks existing
`luac5.1`/`luac` commands. On Windows it may use an existing Lua 5.1 DLL from
known Warcraft Recorder installation locations. It validates version, valid
and invalid syntax, and the 200-local/60-upvalue limits. The maintained
`.tools/lua_runtime.py` DLL adapter compiles without executing addon sources.
It does not need a temporary launcher, download tools, change PATH or write
machine settings. Invalid explicit configuration fails without a fallback.

If resolution or the pinned capability fails, explain the missing/incompatible
Lua 5.1 compiler in Portuguese and stop before modifying the work that needs it.
Preserve files and do not install tooling automatically. Missing executables,
DLLs or adapters are failures, not permission to rediscover another compiler.
All conflict choices, complete staged reviews and commit approvals still apply.

## Dependencies on demand

The maintenance Python helpers use only the standard library; no pip install or
PyYAML is required. The unrelated nameplate test's `lupa` is not an update
dependency. Git is required for sync; accepted library checks may also need SVN
and network access. Check these only at their relevant stage and reuse results.

Only confirmed Cloud setup needs [Cloud preparation](cloud-svn.md).
Normal updates never install tools. At the install checkpoint, load only
`eui-install` for its unchanged menu; physical commands remain local Windows only.
