---
name: eui-update
description: Run the EUI Retail, PTR, or Both update workflow for ordinary update/atualizar commands.
---

# EUI update

Follow the mode routed from `AGENTS.md`. Keep the modes distinct. Before switching branches, account for any uncommitted changes without discarding them. Ensure `upstream` points to `https://github.com/EllesmereGaming/EllesmereUI.git` and `origin` to the user's fork; if `upstream` is absent, add it and verify with `git remote -v`.

## Sync A: Retail from upstream

Run in order: `git fetch upstream`; checkout `main`; merge `upstream/main`; push `origin main`; checkout `12.1-new-features`; pull `origin 12.1-new-features`; merge `upstream/main`. The `main` merge should fast-forward because it receives no direct commits. Use `--no-commit` for a pull or merge that would otherwise make an automatic merge commit; review the staged changes and commit with the required English merge message before pushing. Do not bypass the root staged-review rule.

Report whether `main` had something new or nothing new before reporting Retail. If Retail received nothing, report concisely in Portuguese that the original addon had no new update and `12.1-new-features` is already current. If Retail received commits, report that a new upstream update was merged into `12.1-new-features`. If the `main` or Retail merge conflicts, stop and read [merge conflicts](../../references/merge-conflicts.md), using `upstream/main` as incoming. Continue only after the user's choice. When Retail has no unresolved conflict, push `origin 12.1-new-features`.

## Sync B: PTR from Retail

Checkout `12.1.5-PTR-features` and merge `12.1-new-features`. Report concisely in Portuguese whether PTR was already current with Retail or received and merged Retail changes. On conflict, stop and read [merge conflicts](../../references/merge-conflicts.md), using `12.1-new-features` as incoming. When PTR has no unresolved conflict, push `origin 12.1.5-PTR-features`.

## Mode sequence and checkpoints

- Retail: Sync A, then run [eui-libs](../eui-libs/SKILL.md) on `12.1-new-features`, then the install menu for Retail.
- PTR: Sync A, then Sync B, then run [eui-libs](../eui-libs/SKILL.md) on `12.1.5-PTR-features` only, then the install menu for PTR. Sync A must not cause a Retail install, Retail library update, or any touch to the Retail install folder.
- Both: Sync A, run [eui-libs](../eui-libs/SKILL.md) on Retail, then Sync B, run [eui-libs](../eui-libs/SKILL.md) on PTR. Keep their reports, lockfiles, and approved commits separate. After both syncs, present one install menu for Retail + PTR.

At the install stage, read [eui-install](../eui-install/SKILL.md). The menu is required even if there was nothing new or a conflict was resolved. End with a concise Portuguese report of both sync results as applicable, `main`, conflicts and resolution, external libraries, install result, and line-ending fix scope.

Do clean syncs and already-current checks in the main chat. For a nontrivial conflict, multi-module impact, or possible loss of fork customizations, request the project `deep_reviewer` for one read-only assessment only if it can materially improve the recommendation; then wait for it before presenting the required human choices.
