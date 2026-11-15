# Cloud update delivery

Load this reference for a normal EUI update in confirmed Codex Cloud. Read it
and [incremental ZIP delivery](incremental-zip-delivery.md) before the first
modification of any installable target to capture its initial state. This is an
additional delivery layer: it never replaces, changes, or bypasses
[AGENTS.md](../../AGENTS.md) or the [update skill](../skills/eui-update/SKILL.md).
Checkpoints, conflicts, approvals, merge semantics, libraries, and publication
remain governed by the normal project workflow. Use the frozen `cloud`
environment from the shared maintenance context. The physical installation
checkpoint is intentionally skipped in all modes. Continue directly to this
delivery and the final report after the required validation and publication.
Do not load physical installation instructions, show a menu, ask for local WoW
destinations, or run physical installation or line-ending fixes.
If that workflow fails or pauses for approval or a decision, the update remains
pending; do not generate final artifacts early. Options that do not execute an
update do not automatically receive ZIPs or an update summary.

## Immutable delivery base

Before the first modification of installable state, identify the installable
branch/state according to AGENTS.md and record its full SHA, short SHA, subject,
and addon version when safely determinable. Preserve this state as the immutable
delivery base. Auxiliary or mirror states may be recorded as needed by the
workflow, but never replace the installable base.

For EUI, Retail is `new-features`; PTR is `12.1.7-PTR-features`. Compare each
selected branch's initial state with its final state. In Both mode, capture both
bases before any modification and validate each branch independently. Never mix
Retail and PTR in one ZIP.

## Incremental ZIPs

Apply the purpose selection, naming, delta, manifest and verification rules in
[incremental ZIP delivery](incremental-zip-delivery.md). After the workflow
completes, build separate `*_installer.zip` and `*_commit.zip` artifacts for each
selected branch by default when both purposes have eligible operations. Honor
explicit single-purpose requests. Use the complete cumulative net delta from
each frozen base to its final state, omitting reverted changes. Skip each
purpose with no eligible operations, including no-ops. A deletion-only delta
is eligible.

- Installer paths are relative to `Interface/AddOns`. Compare the distributed
  base and final trees using the maintained EUI packaging policy and helper.
  Write the v1 ZIP comment manifest with runtime removals in
  `installer_deleted_files`.
- Commit paths are relative to the verified Git root. Write the v2 ZIP comment
  manifest with Git removals in `deleted_files`, `file_protection` for every
  operation, the exact target branch, the verified full Git base and the
  required raw SHA-256 hashes. Include matching `config_protection` with
  canonical hashes when the shared contract requires it.

On Cloud Linux, use available compatible tools, such as native Git and Python 3
standard-library ZIP, JSON and hashing support. Verify the same archive and
manifest contracts independently, including exact inventory, CRC, paths,
deletions, base and final hashes, and branch routing. The local Windows paths
and PowerShell applicators are environment-specific. Report applicator and
destination Git checks as inconclusive when they cannot be verified in Cloud.
If the base, required protection or archive contract cannot be established,
report the limitation and withhold the affected ZIP. Keep any independently
validated artifact for the other purpose.

## Update summary

For each branch with a delivered ZIP, write an English summary covering the
complete net functional diff from its initial base to its final state. Include
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
applies to all final installer and commit ZIPs for Retail and PTR.
Upload only validated ZIPs with eligible payload entries or manifest deletions.
If none are produced, skip Drive delivery. Use the exact validated archives
and keep deletion-only archives free of artificial payload entries.
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

Use the [final update report rules](../skills/eui-update/SKILL.md#final-update-report)
for GitHub commit links and publication status. Report each selected branch
separately, including when no ZIP was produced. Report in Portuguese:

- Target; initial and final versions, when available.
- Initial and final subjects with their respective short SHAs. Link only
  verified published commits, including any additional commits shown.
- For each validated ZIP, give the actual artifact download link when
  available, filename, packaged file count, manifest deletion paths (or none),
  and the verification status required by incremental ZIP delivery. Confirm
  that it contains only the final net diff. If a ZIP was skipped or withheld,
  report the purpose and reason.
- State that physical installation was skipped in Cloud.
- For each ZIP with attempted Drive delivery: filename, local size, local SHA-256
  (reuse an existing hash or calculate it when inexpensive), `Google Drive: OK`
  or the actual error/missing capability, and the file link/ID returned by the
  connector when available. Keep delivery status separate from the functional
  update summary and distinguish main-workflow completion from Drive failure.
