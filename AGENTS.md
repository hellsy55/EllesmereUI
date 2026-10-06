# EUI agent instructions

This repository is a fork of https://github.com/EllesmereGaming/EllesmereUI.

## Always-on rules

- Speak to the user in Portuguese, including explanations, summaries, choices, and conflict reports.
- Write everything stored in files or on GitHub in English, including code comments, documentation, commit subjects and bodies, merge messages, PR descriptions, tags, and Git-generated text.
- Commit under the user's name, with only the intended message. Never add AI signatures such as `Co-Authored-By: Codex` or `Generated with Codex`.
- Write each commit subject in English, imperative mood, on one line, covering all meaningful changes concisely. Use `Module (type): brief description`, with a recognizable module and an appropriate type such as `fix`, `feature`, `chore`, or `docs`. Group descriptions of the same module and type with `; `. Keep different types for one module adjacent. Separate sections with `. ` and omit a final period. This applies to sync and library commits too. Examples: `CDM (fix): guard secret spellID values. Raid Tools (feature): disable Convert to Party for raids over 5 members`; `Libraries (chore): update LibSharedMedia to <version>`.
- Before every commit, inspect the staged file list and unstage any unrelated files while preserving their worktree changes. Stage only user-facing addon changes or intentionally maintained project files. Stop and ask if anything staged is unexpected. Show the user `git diff --cached --name-only`, `git diff --cached --name-status`, a concise `git diff --cached --stat`, and the COMPLETE `git diff --cached`, with no size exception. Wait for explicit user approval immediately before `git commit`; prior approval to implement a change does not replace this approval. Apply this checkpoint to normal commits, merge commits, and library commits; do not let a merge create a commit before the checkpoint.
- Preserve preexisting and unrelated changes. Never commit local-only test scripts, scratch files, generated diagnostic helpers, or temporary tooling unless the user explicitly requests that exact file be versioned.
- At maintenance entry, freeze the repository root and execution environment using the shared [maintenance preflight](.agents/references/python-runtime.md). Resolve and freeze Python 3 once before the first mutation or Python helper, whichever comes first; read-only analysis without Python helpers does not require runtime resolution. Discover optional capabilities only when needed and cache their results. Reuse this context across skills and branches; load environment-specific references only when needed. If no compatible runtime is valid, stop before mutation or Python helper execution.
- Never resolve a merge conflict, apply an upstream PR, or vendor an external library without the workflow's explicit human choice. Never run an install without the install menu choice. An install menu choice of option (a) is sufficient confirmation.

## Branches and command routing

- `main` mirrors `upstream/main` on the fork and receives no direct feature commits.
- `new-features` is Retail and syncs only through the most recent commit in `upstream/main` whose SUBJECT starts with `release`, case-insensitive. Exclude all later upstream commits. If that release commit cannot be identified, stop the workflow; never fall back to `upstream/main` HEAD or a tag.
- `12.1.5-PTR-features` is PTR and receives Retail changes by merging `new-features`, after Retail is synced.
- For `update`, `atualizar`, `update retail`, `atualizar retail`, `atualizar o retail`, and close case-insensitive variants, use [eui-update](.agents/skills/eui-update/SKILL.md) in Retail mode.
- For `update PTR`, `atualizar PTR`, and close case-insensitive variants, use [eui-update](.agents/skills/eui-update/SKILL.md) in PTR mode.
- For `update both`, `atualizar ambos`, and close case-insensitive variants, use [eui-update](.agents/skills/eui-update/SKILL.md) in Both mode.
- These modes have different branch and install scopes. Library checks are event-driven as specified in `eui-update`; if triggered, Retail checks Retail, PTR checks PTR, and Both checks each branch separately. If the requested mode is genuinely ambiguous, ask before acting.
- For a GitHub PR URL with a request to implement, apply, port, or evaluate it, including `implement PR <link>` and `implementar PR <link>`, use [eui-implement-pr](.agents/skills/eui-implement-pr/SKILL.md). That skill validates the repository before any further action.
- During an update, load [eui-libs](.agents/skills/eui-libs/SKILL.md) for an explicit library-check request, or after an upstream library-change trigger and the user's choice to check. Load [eui-install](.agents/skills/eui-install/SKILL.md) only at the install-menu stage. Read detailed references only when that stage needs them.

## Delegation

Handle routine work in the main chat without delegation: Git status, clean merges, already-current results, script execution, library checks with no pending updates, authorized installs, and simple diffs or stats. Do not parallelize by default. Request one project `deep_reviewer` only when an independent read-only review is likely to change a consequential decision: a nontrivial conflict, large or ambiguous PR, possible loss of local customizations, multi-module change, difficult regression, or genuinely uncertain library impact. Prefer the main agent when it is sufficient; subagents consume extra tokens. Wait for the review before recommending a human choice. Never let delegation bypass a human checkpoint.
