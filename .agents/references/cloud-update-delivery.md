# Cloud update delivery

Load this reference only when a Cloud prompt explicitly requests it after the
user selects a workflow that executes an update. Read it before the first
modification of any installable target to capture its initial state. This is an
additional delivery layer: it never replaces, changes, or bypasses
[AGENTS.md](../../AGENTS.md) or the [update skill](../skills/eui-update/SKILL.md).
Checkpoints, conflicts, approvals, merge semantics, libraries, publication, and
installation remain governed exclusively by the normal project workflow.
If that workflow fails or pauses for approval or a decision, the update remains
pending; do not generate final artifacts early. Options that do not execute an
update do not automatically receive an installer or update summary.

## Immutable delivery base

Before the first modification of installable state, identify the installable
branch/state according to AGENTS.md and record its full SHA, short SHA, subject,
and addon version when safely determinable. Preserve this state as the immutable
delivery base. Auxiliary or mirror states may be recorded as needed by the
workflow, but never replace the installable base.

For EUI, Retail is `new-features`; PTR is `12.1.5-PTR-features`. Compare each
selected branch's initial state with its final state. In Both mode, capture both
bases before any modification and produce two independent installers, one Retail
and one PTR. Never mix Retail and PTR in one ZIP.

## Incremental installer

Only after the normal workflow has actually completed, calculate the net diff
from each recorded installable base to its final installable state. Package only
the final contents of changed installed-addon files, including new files needed
by the final result. Exclude files identical to the base, unchanged files,
temporary files, tests, operational scripts/helpers, Codex/Cloud tooling,
operational documentation, and packaging artifacts outside the installed addon.
Never package a full distribution or include whole modules/addons merely to
complete it.

Structure each ZIP exactly for extraction over `Interface/AddOns`: main-addon
files belong under `EllesmereUI/...`; sibling addons/modules retain their real
folders, such as `EllesmereUI_RaidFrames/...`, `EllesmereUI_CooldownManager/...`,
and `EllesmereUIOptions/...`. Do not add an outer suite folder. Use a filename
ending in `_installer.zip`, preferably containing a reliable final addon version;
otherwise use the final short SHA. Do not install, extract, or copy the ZIP into
the WoW folder. If the final state requires removals, list the paths separately
in Portuguese as manual deletions; do not attempt to encode deletions in the ZIP.

## Update summary

For each installer, write an English summary covering the complete net functional
diff from its initial base to its final state, not just the last commit. Include
final runtime code, behavior, UI, content, data, functional configuration, and
compatibility changes. Include libraries only when their actually distributed
runtime content changed. Omit reverted intermediate changes, workflow details,
merges as a process, checkpoints, debugging, intermediate conflicts, and discarded
attempts.

Exclude AGENTS.md, agent tools, Codex/Cloud tooling, environment maintenance,
helper scripts, bootstrap, proxies, checkout preparation, operational docs,
tests, CI/CD, checkers, drift baselines, locks, and infrastructure metadata.
Filter by effective final changes, never by commit names or subjects; retain the
functional portion of mixed commits. The summary shown to the user must contain
only functional addon changes present in the final result.

Use `Module (type): item; item. Module2 (type): item`: group the same module/type
with `; `, separate different groups with `. `, and omit the final period. Be
concise without omitting relevant functional changes. Show each summary in one
copy-ready code block.

## Additional Google Drive delivery

Preserve normal Codex artifact delivery. After each final ZIP produced by a
workflow loading this reference is complete and validated, upload that exact
local file using the official Google Drive plugin/connector to `EUI`
(`1h6YGWoHsGcxPwTyoGrfSYQFeGaur8tvb`) under `Codex Artifacts`. This shared rule
applies to all final ZIPs, including independent Retail and PTR installers.
Upload only nonempty ZIPs containing valid packaged files; if none are produced,
skip Drive delivery. Do not regenerate ZIPs for Drive or add artificial entries
for deletions; the existing packaging and manual-deletion rules still apply.
Do not introduce external tools, dependencies, manual OAuth, API keys, or secrets.

After every upload, read the uploaded file's metadata again through the connector
and verify its filename, existence, and parent folder against the destination
above. Compare its size with the local ZIP when the remote size is available.
An upload response alone is not success; report `Google Drive: OK` only after
successful readback and matching metadata.

Drive is an additional post-generation delivery channel, never a prerequisite
for merge, update, commit, or push. If the connector or write capability is
unavailable, or upload or readback fails, report the actual error or missing
capability separately from the completed main workflow. Never claim Drive
success or revert or invalidate a correctly completed update/commit because
Drive delivery failed. Continue delivering any remaining valid final ZIPs.

## Final delivery report

For each target/installer, report in Portuguese:

- Target; initial and final versions, when available.
- Initial subject + short SHA; final subject + short SHA; `initial -> final`.
- ZIP filename, packaged file count, and required manual deletion paths (or none).
- Confirmation that the ZIP contains only the final net diff and that no files
  were installed into the WoW folder.
- For each ZIP with attempted Drive delivery: filename, local size, local SHA-256
  (reuse an existing hash or calculate it when inexpensive), `Google Drive: OK`
  or the actual error/missing capability, and the file link/ID returned by the
  connector when available. Keep delivery status separate from the functional
  update summary and distinguish main-workflow completion from Drive failure.
