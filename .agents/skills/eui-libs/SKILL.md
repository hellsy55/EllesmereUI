---
name: eui-libs
description: Check and, only after approval, vendor EUI external libraries on the branch selected by the update workflow.
---

# EUI external libraries

The external libraries in `.pkgmeta` are fetched by the release packager; a branch merge does not update them automatically. Run this skill only after the update workflow's explicit-request trigger or after the user accepts a check prompted by upstream library changes. Run on the selected branch after sync and before its install menu. Retail checks only Retail; PTR mode checks only PTR even though Sync A ran; Both checks each branch separately when the trigger applies.

The checker prints each library's comparable baseline and upstream version plus aggregate status counts. Interpret the reported statuses and counts, not just the exit code. Exit 0 means there are no pending, DRIFT, or UNKNOWN results; both current and accepted-drift are allowed. A nonzero exit does not necessarily mean the check is incomplete: pending updates also return nonzero. Git and SVN (for WowAce sources) must be available for the accepted check; do not install them from the workflow.

The checker states are:

- `current`: the checker has proven the library is up to date and the local packaged payload is equivalent to the upstream packaged payload.
- `accepted-drift`: a previously audited payload difference whose exact identity and fingerprints match the accepted baseline. This is healthy, but must remain visible and separate from `current`.
- `pending`: proven version, revision, or commit advancement that enters the update review and decision flow.
- `DRIFT`: a deterministic payload difference without proven advancement that does not match an accepted baseline. This blocks the workflow and must not be treated as an automatic update.
- `UNKNOWN`: inconclusive querying, parsing, or evidence. This blocks the workflow and must never be called current.

Only in a confirmed Cloud environment, and only when setup is needed, consult
[Cloud preparation](../../references/cloud-svn.md); do not bootstrap tools from the update workflow.
The checker reports CHECKED and status counts, and comparable local/upstream versions.
Missing lock records are not proof of outdated or unvendored libraries: use a
declared pin or a safely comparable local version. Missing evidence remains UNKNOWN.

Reuse the frozen [maintenance context](../../references/python-runtime.md) from eui-update, or initialize it once before a standalone library check. Check required Git/SVN availability once when this accepted stage first needs them and retain the result across Both branches. Run `<python_runtime> .tools/check_lib_updates.py` on the current branch, then interpret the results in this order:

1. If UNKNOWN > 0, report that the check is inconclusive; if DRIFT is also present, report that drift too. Do not claim the libraries are current, do not vendor, and stop.
2. If UNKNOWN=0 and DRIFT > 0, report the drift and stop for investigation. Do not treat it as an update, apply an automatic correction, or vendor.
3. If UNKNOWN=0, DRIFT=0, and pending > 0, follow [library review](references/library-review.md). Show the current and new versions and ask for the human choice before any `--apply`.
4. If pending=0, DRIFT=0, and UNKNOWN=0, consider the check healthy and continue without pausing or delegating. Report concisely in Portuguese; if accepted-drift is present, mention it compactly and keep it separate from current. Never claim accepted-drift is current.

Never vendor or commit a library before displaying its found version and receiving explicit authorization. For each approved library, run `<python_runtime> .tools/check_lib_updates.py --apply <short-name>`, show `git diff --stat`, then stage only intended files and perform the complete root staged review. Wait for explicit approval immediately before committing; approval to vendor does not replace commit approval. Make one English commit per library or one clear batch commit for an approved all-libraries choice, only after the appropriate approvals. Use a subject such as `Libraries (chore): update <lib name> to <version>`, with no AI signature. Push `origin <current branch>`, then continue to the install menu. Never mix branches' lockfiles or commits.
