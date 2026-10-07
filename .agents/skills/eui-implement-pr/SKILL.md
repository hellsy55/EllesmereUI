---
name: eui-implement-pr
description: Evaluate or implement a PR from EllesmereGaming/EllesmereUI on a user-chosen EUI branch.
---

# Implement an upstream PR

First validate that the URL identifies a PR on `EllesmereGaming/EllesmereUI`. If it is another repository, stop and ask before doing anything else. Ask which target branch (`new-features` or `12.1.5-PTR-features`) before any analysis; never assume a default.

After repository and target selection, initialize or reuse the root and environment in the shared [maintenance context](../../references/python-runtime.md). Read-only PR metadata, changed paths, and analysis without Python helpers do not require Python preflight. Resolve and freeze `python_runtime` only before the first mutation/application or Python helper, whichever comes first; discover optional capabilities only when needed and cache them. Reuse all resolved values across skills and branches through application and publication.

Start with compact PR metadata (`gh pr view <url> --json number,title,state,baseRefName,headRefName,additions,deletions,changedFiles`) and a changed-file list (`gh pr view <url> --json files`). Identify affected modules and change size before fetching `gh pr diff <url>`. For a large PR, capture the diff locally and read only the relevant file sections. Fetch full raw files only if the diff cannot show the real effect, such as logic in untouched sections, renamed symbols, or dependencies on other functions. Compare affected code with the chosen local branch; do not analyze unaffected files deeply.

Analyze a small, clear PR in the main chat. For a large or ambiguous PR, changes across modules, a difficult regression, or possible loss of fork customizations, request one project `deep_reviewer` for a read-only independent assessment only when it can materially improve the gain/loss analysis; wait for it before reporting options. Do not delegate merely because a PR exists.

Before applying anything, stop and report in Portuguese and practical terms: what the user gains, what behavior or fork customization is lost or overwritten, and what stays the same. For a real Git conflict, read [merge conflicts](../../references/merge-conflicts.md) and present its functional explanation and four choices without code by default. For a large change without a technical conflict, still offer: apply as-is, apply with adaptation, skip that part, or apply nothing. Wait for the user's explicit choice; never apply a PR before this report and approval.

After an approved application, stage only intended changes, show the root staged review, and commit using the required English imperative subject and body without AI signatures. Include the PR number and upstream source in the commit body for traceability.

## Optional incremental installer and Drive delivery

Record the chosen branch's committed state immediately before this workflow
begins as the immutable installer base. This delivery step is independent of
`cloud-update-delivery.md`; do not load or depend on that reference. Preserve all
existing analysis, adaptation, event-driven library checks, validations, staged
review, explicit pre-commit approval, and commit/push rules. Never install
automatically.

Only after the final commit/push has completed and been validated, check the net
functional installable changes from the recorded base to the final committed
state. If there are none, do not offer an installer. Otherwise ask in Portuguese:
`Deseja que eu gere também um ZIP incremental pronto para instalar?`
If declined, finish normally. If accepted, generate an `_installer.zip` containing
only final contents of eligible added or modified runtime files from that net
diff, with real addon folders ready for extraction over `Interface/AddOns`.
Exclude unchanged files, infrastructure, documentation, AGENTS, tooling, and all
noninstallable files. Do not encode deletions or add artificial entries; list
deleted installable paths separately for manual removal. Do not generate an
empty ZIP, make another commit/push, or install the artifact.

When an installer is actually generated, preserve normal Codex artifact delivery
and upload the same final local file through the official Google Drive
plugin/connector to `Codex Artifacts/EUI`, folder ID
`1h6YGWoHsGcxPwTyoGrfSYQFeGaur8tvb`. Do not regenerate or recreate it for Drive.
Before upload, verify the final ZIP exists, its size is greater than zero, and
it contains at least one valid installable file. Reuse or calculate its local
SHA-256 when inexpensive and available. Do not introduce rclone, manual OAuth,
API keys, secrets, external tools, or dependencies.

Use the returned file ID for a new connector metadata readback after upload.
Confirm existence, the exact filename/title, the destination folder ID in
`parents`, and remote size equal to local size when `size` is available. Retain
the returned link/ID when available; do not require `trashed` in the readback.
An upload response alone is not success. Report `Google Drive: OK` only after
readback validates the metadata; missing IDs or mismatches are delivery errors.

Drive is only an additional post-generation delivery channel. If the plugin,
upload, or readback fails, preserve Codex delivery and report the actual error
or missing capability separately. Never claim Drive success, revert, invalidate,
or redo a correctly completed commit/push because Drive delivery failed.

For each generated installer, report compactly in Portuguese: ZIP filename,
packaged file count, size, local SHA-256 when available, manual deletions or none,
`Google Drive: OK` or the actual error, and the returned Drive link/ID when
available. If no valid ZIP can be generated, report that and any manual deletions
without attempting an empty upload.
