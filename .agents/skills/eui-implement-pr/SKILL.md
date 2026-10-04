---
name: eui-implement-pr
description: Evaluate or implement a PR from EllesmereGaming/EllesmereUI on a user-chosen EUI branch.
---

# Implement an upstream PR

First validate that the URL identifies a PR on `EllesmereGaming/EllesmereUI`. If it is another repository, stop and ask before doing anything else. Ask which target branch (`new-features` or `12.1.5-PTR-features`) before any analysis; never assume a default.

Start with compact PR metadata (`gh pr view <url> --json number,title,state,baseRefName,headRefName,additions,deletions,changedFiles`) and a changed-file list (`gh pr view <url> --json files`). Identify affected modules and change size before fetching `gh pr diff <url>`. For a large PR, capture the diff locally and read only the relevant file sections. Fetch full raw files only if the diff cannot show the real effect, such as logic in untouched sections, renamed symbols, or dependencies on other functions. Compare affected code with the chosen local branch; do not analyze unaffected files deeply.

Analyze a small, clear PR in the main chat. For a large or ambiguous PR, changes across modules, a difficult regression, or possible loss of fork customizations, request one project `deep_reviewer` for a read-only independent assessment only when it can materially improve the gain/loss analysis; wait for it before reporting options. Do not delegate merely because a PR exists.

Before applying anything, stop and report in Portuguese and practical terms: what the user gains, what behavior or fork customization is lost or overwritten, and what stays the same. For a real Git conflict, read [merge conflicts](../../references/merge-conflicts.md) and present its functional explanation and four choices without code by default. For a large change without a technical conflict, still offer: apply as-is, apply with adaptation, skip that part, or apply nothing. Wait for the user's explicit choice; never apply a PR before this report and approval.

After an approved application, stage only intended changes, show the root staged review, and commit using the required English imperative subject and body without AI signatures. Include the PR number and upstream source in the commit body for traceability.
