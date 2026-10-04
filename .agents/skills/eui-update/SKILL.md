---
name: eui-update
description: Run the EUI Retail, PTR, or Both update workflow for ordinary update/atualizar commands.
---

# EUI update

Follow the mode routed from `AGENTS.md`: Retail runs Sync A; PTR runs Sync A then Sync B; Both runs Sync A then Sync B. Keep branch, install, and triggered library scopes separate. Account for uncommitted changes before switching branches. Verify that `upstream` points to `https://github.com/EllesmereGaming/EllesmereUI.git` and `origin` to the user's fork; add a missing `upstream` and verify it before continuing.

## Compact preflight and fetch

Use `git status --porcelain=v1 -uall` once before mutations, `git branch --show-current`, and `git rev-parse` for relevant refs. Preserve preexisting changes. Fetch upstream once per execution, quietly; fetch origin in the same invocation when possible (`git fetch --quiet --multiple upstream origin`). Reuse fetched refs. Do not print fetch progress or raw command output unless an error needs explanation. Refresh status only after an operation that could change the working tree. Use `git merge-base --is-ancestor`, `git rev-list --count`, and `git diff --name-only` or `--name-status` rather than a full log or diff for initial decisions.

Before any checkout or merge, compare ancestry. If the source is already an ancestor of the destination, skip that checkout and merge. Do not run a merge merely to get `Already up to date`. If refs diverge unexpectedly, stop for the applicable human conflict/branch decision; never overwrite commits. Report `main` before Retail, even for a no-op.

## Sync A: Retail from upstream

`main` mirrors `upstream/main`; never use `main` as a bridge to Retail. If `main` is behind `upstream/main`, check out `main`, fast-forward only, and push `origin main` only when the remote needs it. Check `origin/main` ancestry before pushing and stop on unexpected remote divergence. If local `main` diverges from upstream, stop and read [merge conflicts](../../references/merge-conflicts.md) before any resolution.

For `new-features`, first compare the local ref with fetched `origin/new-features`. Fast-forward a behind local ref; stop on divergence for a human choice. Before merging, record `base = git merge-base new-features upstream/main` and the exact incoming upstream range `base..upstream/main`. Count commits with `git rev-list --count new-features..upstream/main`. If `upstream/main` is already an ancestor of Retail, skip checkout and merge. Otherwise check out Retail, fast-forward if possible, or use `git merge --no-commit upstream/main` when a merge commit is required. Review staged changes and commit using the required English merge subject before pushing. Stop on a real conflict and read [merge conflicts](../../references/merge-conflicts.md); never resolve before the user's choice. Push Retail only if its ref changed or its remote is behind. A no-op reports that upstream has no new update and Retail is current.

## Sync B: PTR from Retail

Compare `12.1.5-PTR-features` with fetched `origin/12.1.5-PTR-features`; fast-forward a behind local ref and stop on divergence. If Retail is already an ancestor of PTR, skip checkout and merge. Otherwise check out PTR, fast-forward if possible, or merge Retail with `--no-commit`, staged review, and the required English merge subject. On conflict, stop and read [merge conflicts](../../references/merge-conflicts.md), using Retail as incoming. Push PTR only if its ref changed or its remote is behind. PTR mode never touches the Retail install folder or performs a Retail library check.

## Targeted risk triage

When Sync A has incoming commits, first list only changed paths in `base..upstream/main`. Compare them with paths changed by fork commits since `base` on the target branch. If there is no reasonable file/module overlap, skip semantic review. If paths or modules overlap, inspect only their relevant diff and surrounding functions for features added in the same function, flow, or functional region, including interference without a textual conflict. For Sync B, compare Retail's incoming changed paths with PTR-only changed paths since their merge base in the same way. Explain any practical feature risk in Portuguese. Request exactly one read-only `deep_reviewer` only when a complex overlap could change a consequential recommendation; give it only the relevant context and wait before asking the user to choose. Routine status, no-op, clean non-overlapping merges, and mechanical library detection stay in the main chat.

## Mode sequence and checkpoints

- Retail: Sync A, then the Retail install menu.
- PTR: Sync A, then Sync B, then the PTR install menu. Sync A must not cause a Retail install, Retail library update, or any touch to the Retail install folder.
- Both: Sync A, then Sync B, then one install menu for Retail + PTR.

## Event-driven external libraries

Ordinary updates do not load `eui-libs`, run the external version checker, ask about libraries, or mention them in the report. A clear user request to check libraries or update with libraries triggers the normal branch-scoped [eui-libs](../eui-libs/SKILL.md) stage after sync.

The other trigger is an upstream change in the exact incoming range recorded before Sync A. Run `py -3 .tools/classify_library_range.py <base> upstream/main` only when the range is nonempty. This local-only command summarizes affected libraries using `.pkgmeta` externals, library directories, and library metadata; it does not query releases or vendor files. If it reports no library changes, continue silently. If it reports changes, summarize only the added, modified, or removed libraries and ask exactly: `O upstream alterou libraries. Deseja verificar se há atualizações nas demais libraries? a) Sim b) Não`. Do not load `eui-libs` or run the checker until the user chooses a). If the user chooses b), continue without claiming the other libraries are current; when needed, say only `Demais libraries: não verificadas`. In Both mode, an accepted check applies to Retail after Sync A and PTR after Sync B, with separate reports, lockfiles, approvals, and commits.

At the install stage, read [eui-install](../eui-install/SKILL.md). Preserve its exact menu and authorization even after a no-op or resolved conflict. Report in a few Portuguese progress lines: preflight scope and clean/dirty state; upstream commit count and only branches that changed; then the install checkpoint. Surface errors, conflicts, feature risks, and required choices. Keep hashes, full status, fetch output, checkout output, temporary paths, copied-file lists, and line-ending details out of routine output. Report line-ending fix scope only if relevant.
