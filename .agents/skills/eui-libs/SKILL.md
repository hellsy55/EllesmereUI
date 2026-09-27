---
name: eui-libs
description: Check and, only after approval, vendor EUI external libraries on the branch selected by the update workflow.
---

# EUI external libraries

The libraries in `.pkgmeta` are outside upstream and fork Git history; the release packager normally fetches them. A branch merge does not update vendored libraries. Run once on the branch specified by the update workflow, immediately after that branch's sync stage and before its install menu. Retail checks only Retail; PTR mode checks only PTR even though Sync A ran; Both checks each branch separately.

Run `python scripts/check_lib_updates.py` on the current branch. If nothing is pending, report concisely in Portuguese that no external library is outdated on this branch and continue without pausing or delegating. If updates are pending, read [library review](references/library-review.md) before offering choices. Never vendor or commit a library before displaying its found version and receiving explicit authorization. For each approved library, run `python scripts/check_lib_updates.py --apply <short-name>`, show `git diff --stat`, then stage only intended files and perform the root staged review before committing. Make one English commit per library or one clear batch commit for an approved all-libraries choice. Use a subject such as `Libraries (chore): update <lib name> to <version>`, with no AI signature. Push `origin <current branch>`, then continue to the install menu. Never mix branches' lockfiles or commits.
