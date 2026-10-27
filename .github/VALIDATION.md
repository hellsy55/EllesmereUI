# Validate an incremental ZIP before a manual commit

This procedure checks the final Git working tree after an incremental ZIP is
applied. It does not apply ZIPs, fix files, stage changes, install addons, update
libraries, synchronize branches, commit, or publish. It does not change the Codex
maintenance workflows or the external ZIP applicator.

## Establish the input

Before applying a ZIP, record the repository root, destination branch, full HEAD
SHA, and existing staged, unstaged and untracked paths. Use native Git for this
evidence. Confirm that the ZIP was prepared against that branch and base. Preserve
unrelated local edits and review ZIP deletions as well as replacements and new
files. A ZIP does not carry Git ancestry; a filename is not proof of its base.

After application, confirm the same branch and HEAD. For this procedure the
destination is exactly `new-features` (Retail) or `12.1.7-PTR-features` (PTR).
Do not infer the target from TOC Interface values or normalize another client's
files. A base mismatch, unresolved index or unavailable history is inconclusive:
stop and review the inputs instead of guessing a reference.

## Resolve dependencies once

Follow `.agents/references/python-runtime.md`. Resolve a compatible Python 3 once
with `.tools/python_runtime.py`; retain its absolute executable. Python 3.12 is a
useful common version with the packaging CI. Use `-B` on subsequent Python calls.
The validators use the standard library; no pip installation is needed.

Resolve the compiler with the same Python:

```text
<python_runtime> -B .tools/lua_runtime.py --resolve
```

This checks Lua 5.1 syntax and the 200-local/60-upvalue limits, not just a version
banner. Pin the returned native compiler through process-local `LUAC`, or the
returned existing DLL through process-local `LUA51_DLL` with `LUAC` unset. A
missing/incompatible compiler prevents a complete validation; tests skipped for
that reason do not count as a pass. Do not install tools or change machine PATH
as part of validation.

Git and Bash must be available. On Windows use Git for Windows Bash explicitly
when needed. The locale extractor uses GNU grep, sed, sort, mktemp, wc, tr, cat,
cmp and rm. An unavailable tool means inconclusive validation.

## Check the final working tree

The placeholders below are arguments to replace, not literal shell syntax.
In PowerShell use `& '<absolute executable>'` for an executable path with spaces.
Run from the repository root, using the previously recorded full base SHA:

```text
<python_runtime> -B .tools/guardrails.py --base <full-SHA-before-ZIP>
<python_runtime> -B .tools/normalize_tocs.py check --target <destination-branch>
<native-git> diff --check
<native-git> diff --cached --check
<bash> .tools/extract-locale-keys.sh --check
```

Run Guardrails before every commit as required by AGENTS.md, even for documentation.
Without `--head`, it reads the final working tree, including staged, unstaged and
new non-ignored Lua. Do not add `--head HEAD`: that reads committed blobs instead
of the applied ZIP. Ignored Lua is not automatically included; review ignored/new
ZIP payload paths separately. Whitespace checks do not inspect untracked files;
review new files explicitly before staging and committing them.

The baseline is compared through its common ancestor with HEAD. It must be the
recorded pre-ZIP commit, not a moving remote ref, `HEAD~1`, or a guessed upstream
release. Guardrails logs the requested base, head context and effective merge-base.
Missing commits, unrelated histories and Git operational failures stop validation.

Always use TOC `check` here. Never run `fix`, a release wrapper, a library apply
command, or an installer as a validation shortcut. Run locale `--check` when Lua,
the key list or extraction infrastructure is affected; it can also be run as a
full-tree consistency check. No-argument locale generation remains an intentional
editing operation whose result requires review.

Locale comparison accepts Git's CRLF checkout representation by stripping CR only
in a temporary comparison copy. The real key-list bytes and timestamps are retained;
generation still produces the original canonical LF format.

## Interpret results and preserve evidence

| Result | Meaning |
| --- | --- |
| Passed | The applicable command completed with exit 0, valid prerequisites and the intended input/scope. |
| Failed | An actual violation was found; for Guardrails/locales exit 1 denotes a validation failure. Review and correct separately. |
| Inconclusive | Missing tools/history, Git/I/O errors, invalid arguments, skipped required compiler tests, or an input mismatch prevent a conclusion. Guardrails/locales use exit 2 for these errors. |
| Not applicable | A conditional suite is outside the changed paths. This is not an inherited pass from another SHA. |

TOC `check` uses exit 1 for validation **or I/O** failures and exit 2 for argument
errors; read its diagnostic to distinguish failed from inconclusive. Do not infer
the classification from a universal exit-code table.

Record command, branch, base, result, applicable scope and compiler descriptor.
Compare file bytes/mtime and the index before/after when verifying the no-write
contract. The commands may use system temporary files but must not rewrite project
files or stage changes. Python `-B` prevents imported helper bytecode in the tree.
Git status alone cannot prove absence of an ignored artifact or timestamp change.

Review the complete diff in GitHub Desktop, including new files and deletions.
Select only intended files for the manual commit. If content changes after checks,
rerun the affected checks. Preserve the existing complete staged-review/approval
checkpoint whenever Codex will perform a commit; this procedure grants no approval.

Run the official regression suites when their validators or infrastructure change:

```text
<python_runtime> -B .tools/tests/test_guardrails.py
<python_runtime> -B .tools/tests/test_maintenance.py
<python_runtime> -B .tools/tests/test_toc_policy.py
<python_runtime> -B .tools/tests/test_locale_keys.py
<python_runtime> -B .tools/tests/test_validation_workflows.py
```

Packaging/installer tests remain conditional on their infrastructure and run in
disposable fixtures. Do not run real installers or library updates for a Lua-only
ZIP. The checks do not certify in-game behavior, taint safety or secret-value use.
TOC triggers do not cause Guardrails to re-audit unchanged Lua lines that become
loadable after a TOC-only change; review that loading change independently.

## Verify the published commit

After the manual commit/push, record its full SHA. Check the matching repository,
branch, workflow path, event `push`, `head_sha`, latest run attempt, job results and
`conclusion: success`. The workflow's checked-out SHA must equal the event SHA.
An old green run, a skipped workflow, or a rerun of another commit is not approval.

Guardrails runs on every push to main/Retail/PTR. Locale, TOC and Packaging retain
path filters: absence can mean not applicable, or a trigger/configuration problem;
verify the changed paths before deciding. PR checks deliberately test GitHub's
merge revision, with the immutable PR base SHA. They do not replace the push check
on the published branch commit.

Normal pushes use the event's previous SHA. Force-pushes with an available previous
commit and common ancestry use their common ancestor and report the event's forced
flag. Initial pushes, unavailable previous commits, checkout mismatches and
unrelated histories fail explicitly; there is no automatic alternative baseline.
An initial/root history needs a separately reviewed validation policy. A rerun
does not restore unavailable history or validate a newer commit.

No new workflow_dispatch or hooks are needed. Existing Packaging dispatch remains
unchanged. Checks report findings; they do not prevent direct pushes without a
separately approved repository protection policy.

## Deliver to both maintained branches

Review and approve the local implementation before committing. Keep pending work
on its original branch. After an approved commit, transport the reviewed change to
the other branch only through an explicitly approved integration, and rerun checks
with that branch's own base and TOC target. Do not edit main, switch with pending
changes, or treat successful PTR tests as validation of Retail's different tree.
