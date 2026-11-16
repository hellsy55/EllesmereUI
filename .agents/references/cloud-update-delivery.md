# Cloud update delivery

Load this reference for a normal EUI update in confirmed Codex Cloud. Read it
and [incremental ZIP delivery](incremental-zip-delivery.md) before the first
modification of any installable target to capture its initial state. For normal
Cloud updates, the incremental delivery reference supplies only the shared
installer v1 manifest, safety and validation contracts. Its incremental ZIP
and v2 commit ZIP rules apply to Local delivery and other workflows that
explicitly require them. This delivery layer preserves
[AGENTS.md](../../AGENTS.md) and the [update skill](../skills/eui-update/SKILL.md).
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

## Complete installer ZIPs

Deliver one complete installer ZIP for each selected branch with an eligible
distributed delta. Use `EllesmereUI_<description>_installer.zip` for Retail and
`EllesmereUI_<description>_PTR_installer.zip` for PTR. Normal Cloud updates
produce no commit ZIPs. Git commits and pushes follow the normal workflow.

Compare each immutable base and final branch state under the maintained
[snapshot packaging policy](../../.tools/install/README.md), with the
[TOC policy](toc-compatibility.md) for that branch. Net distributed additions,
byte changes and removals determine eligibility, runtime deletions and the
functional summary. Deletion-only changes qualify. Skip no-ops and changes
limited to operational files. Withhold delivery and report an invalid or empty
final distribution.

Package every file in the validated final distribution, including unchanged
runtime files, modules, assets and vendored libraries required for a clean
installation. Apply the literal `.pkgmeta` ignores, moves and distribution
exclusions. Keep addon folders as siblings directly under `Interface/AddOns`,
with archive paths relative to that directory. Validate manifests and their
file references, and preserve final file bytes. Exclude repository metadata,
tooling, backups and nested archives.

Store compact UTF-8 JSON in the native ZIP/EOCD comment using the installer
contract in the incremental delivery reference: `schema_version: 1`,
`repository: "EllesmereUI"`, an empty `deleted_files` array, and exact
base-to-final distributed removals in `installer_deleted_files` (empty when
none). Use only installer metadata and respect the 65,535-byte comment limit.

Use compatible Cloud tools such as native Git and the Python 3 standard
library. PowerShell is not required to generate the ZIP. The independent
[packaging integration gate](packaging-integration.md) and its audit requirements
still apply. Reopen each ZIP and verify CRC, exact inventory and SHA-256 against
the full final distribution, EOCD schema, exact removals, structural and TOC
compatibility, and Retail/PTR routing. Reject unsafe paths, links, case-folded
duplicates, file/parent collisions and overlaps with removals. Report static
contract checks separately from Windows applicator tests and mark unverified
applicator or destination checks inconclusive. Withhold any ZIP whose base,
distribution or archive contract cannot be verified.

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
applies to all final installer ZIPs for Retail and PTR.
If none are produced, skip Drive delivery.
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
  and the installer verification status. Confirm that it contains the complete
  final installable distribution. If a ZIP was skipped or withheld, report
  the reason.
- State that physical installation was skipped in Cloud.
- For each ZIP with attempted Drive delivery: filename, local size, local SHA-256
  (reuse an existing hash or calculate it when inexpensive), `Google Drive: OK`
  or the actual error/missing capability, and the file link/ID returned by the
  connector when available. Keep delivery status separate from the functional
  update summary and distinguish main-workflow completion from Drive failure.
