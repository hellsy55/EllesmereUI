---
name: eui-libs
description: Check and, only after approval, vendor EUI external libraries on the branch selected by the update workflow.
---

# EUI external libraries

The external libraries in `.pkgmeta` are fetched by the release packager; a branch merge does not update them automatically. Run this skill only after the update workflow's explicit-request trigger or after the user accepts a check prompted by upstream library changes. Run on the selected branch after sync and before its install menu. Retail checks only Retail; PTR mode checks only PTR even though Sync A ran; Both checks each branch separately when the trigger applies.

The checker prints each library's comparable baseline and upstream version plus an aggregate result. A nonzero exit or unresolved source means the check is incomplete; report the failure and never claim those libraries are current or vendor from an incomplete check. Git and SVN (for WowAce sources) must be available for the accepted check; do not install them from the workflow.

Cloud SVN preparation belongs to the canonical [Cloud setup reference](../../references/python-runtime.md)
and its [rootless SVN bootstrap](../../references/cloud-svn.md), not the update workflow.
The checker reports CHECKED and UNKNOWN, and comparable local/upstream versions.
Missing lock records are not proof of outdated or unvendored libraries: use a
declared pin or a safely comparable local version. Missing evidence remains UNKNOWN.

Reuse `python_runtime` from eui-update, or run the shared [Python preflight](../../references/python-runtime.md) once before a standalone library check. Run `<python_runtime> .tools/check_lib_updates.py` on the current branch. If nothing is pending, report concisely in Portuguese that no external library is outdated on this branch and continue without pausing or delegating. If updates are pending, read [library review](references/library-review.md) before offering choices. Never vendor or commit a library before displaying its found version and receiving explicit authorization. For each approved library, run `<python_runtime> .tools/check_lib_updates.py --apply <short-name>`, show `git diff --stat`, then stage only intended files and perform the root staged review before committing. Make one English commit per library or one clear batch commit for an approved all-libraries choice. Use a subject such as `Libraries (chore): update <lib name> to <version>`, with no AI signature. Push `origin <current branch>`, then continue to the install menu. Never mix branches' lockfiles or commits.
