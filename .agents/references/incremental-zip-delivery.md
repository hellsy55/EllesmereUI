# Local incremental EUI ZIP delivery

## Select purpose and freeze the batch

For EUI changes intended for in-game testing and manual commit, deliver separate
`*_installer.zip` and `*_commit.zip` artifacts per applicable branch by default.
For a cumulative implementation batch, carry earlier authorized changes still
relevant to that branch/base, even when the latest reply only mentions one of
them. Use one cumulative English commit summary for the same logical batch,
identifying any branch-specific variation. Honor explicit test-only, commit-only,
and partial checkpoints. Temporary upstream PR testing is installer-only until
integration is requested. A review alone produces no ZIP. Skip a purpose with no
eligible net operations, including a no-op. A deletion-only delta is eligible.
Full standalone distributions of the existing addon require an explicit request.

Freeze the real Git root, fork identity, target branch, full original base commit
and intended final state for each branch before producing a delta. Keep the same
base across cumulative rounds unless the user explicitly establishes a new batch
or reconciles a changed base. Preserve and exclude unrelated local changes.
Compare the original base with the complete final state, discarding intermediate
operations that were reverted. Both-mode packages use independent bases, Git
objects and validation. Name them `EllesmereUI_<description>_installer.zip` and
`EllesmereUI_<description>_commit.zip` for Retail (`new-features`), inserting
`_PTR` immediately before the purpose for `12.1.7-PTR-features`. Use `/` as the archive path separator. Deliver the current round's
artifacts and keep installer and commit ZIPs separate even with matching paths.

## Build two independent deltas

- Commit entries are regular files added or replaced relative to the actual Git
  root. Record removals in `deleted_files`. Do not insert an addon-name wrapper.
  Include documentation and tooling only when intentionally in scope.
- Installer entries are additions or replacements relative to
  `Interface/AddOns`. Compare the distributed base and final trees using the
  maintained EUI packaging policy and helper. Account for `.pkgmeta` exclusions,
  moves and TOC loading policy, including unchanged Git files entering/leaving
  distribution. Core root files such as `EllesmereUI.lua` become
  `EllesmereUI/EllesmereUI.lua`; separately packaged modules keep sibling roots.
  Record runtime removals only in `installer_deleted_files`, independently of
  Git removals. Keep repository metadata, protected configuration, tooling,
  backups, temporary helpers and nested ZIPs out of the installer. Check addon
  roots against the installed or supplied TOCs. Agree on identical bytes for
  files common to both purposes; preserve binary bytes, BOM and final encoding.
- Include only changed payload entries. Reject absolute paths, dot segments,
  traversal, Windows-unsafe names, case-folded duplicates, file/parent
  collisions, links and paths that overlap deletions. Record exact canonical
  spelling and distinguish removals explicitly; extraction alone cannot delete.

## Use the operational contracts

On local Windows, inspect the current copies of `ApplyAddonInstaller.ps1`,
`ApplyAddonUpdate.ps1` and `BuildProtectedAddonZip.py` in
`%USERPROFILE%\Desktop\Addon Update Script` (or the verified operational
location). Compare naming, routing, schema, deletion behavior, hashes and path
rules against the scripts actually used. Report missing paths or incompatible
versions. Keep the tools external and leave existing approval, backup and
rollback behavior with the operational scripts.

Both formats store compact UTF-8 JSON in the native ZIP/EOCD comment. Include
`repository: "EllesmereUI"`, `deleted_files` and `installer_deleted_files`
arrays (empty when no applicable removals). The independent installer uses
`schema_version: 1` and applies only the installer deletion array. The default
Retail destination and explicit PTR/XPTR selection are handled by
`ApplyAddonInstaller.cmd`/its PowerShell script. Never route a PTR ZIP to Retail
or silently fall back to another client. The installer previews the changes,
uses its existing confirmation for effective deletions and preserves its
backup/rollback path. After application the selected client can run `/reload`.

The commit ZIP uses `schema_version: 2` and `file_protection` with
`version: 1`, `hash_mode: "sha256-raw-v1"`, the exact `target_branch`,
verified full lowercase `base_commit` and `files` covering every Git payload
entry and Git deletion exactly once. Each record carries `path`,
`operation` (`add`, `replace`, `delete`), `base_sha256` (raw original Git
blob, or JSON null for add) and `final_sha256` (raw extracted bytes, or JSON null
for delete). When adding or replacing `.pkgmeta` or `.tools/toc_policy.json`,
also require matching branch/base and exact affected-path coverage in
`config_protection`, version 1, using `sha256-utf8-crlf-to-lf-v1` for its
separate canonical hashes. Reject protected configuration deletions.
Use the verified operational `BuildProtectedAddonZip.py` to upgrade a separate
v1 commit input to the final v2 output with `--zip`, `--output`, `--repo`,
`--repository EllesmereUI`, `--branch`, and `--base`. Verify the result
independently. If the 65,535-byte comment limit is exceeded, report it and
reconcile the delivery scope without stripping protection. An unproven base
blocks protected commit delivery; never invent a base or silently downgrade.

## Verify and report

Use native Git to verify the destination clone's origin, active branch, exact
base object and ancestry to HEAD. Compare every affected path against the base,
HEAD, actual checkout and index, accounting for Git filters, unrelated edits
and ignored/untracked collisions. A later HEAD with unchanged affected content
can still match; distinguish a missing object, non-ancestry, Git failure and
overlapping changes. Plain fetch of a verified origin may supply a missing
object; reconcile divergence without reset, force, or a substituted SHA. If the
destination checkout is inaccessible, report local Git preflight inconclusive
and provide the exact branch/base and verification commands. Distinguish
verification of an authored working tree from application to a separate clone.

Reopen the final archives and check CRC, exact entry inventory, comment schema,
paths, deletions, raw hashes, any protected configuration hashes, same-file
payload equality and client routing. Compare static contracts and, when
possible, test operational validation in disposable fixtures without touching a
real destination. Report each package's applicator status (passed real test,
passed static contract, failed, or inconclusive), local Git preflight status,
branch/base, checked scope and deletions. Name the correct operational
applicator for each purpose. Keep a structurally valid protected ZIP intact
when applicator support is unconfirmed, and recommend supervised manual review
if needed. Delivering or testing a ZIP does not authorize commit, push, a
physical install, or changing external scripts. Retain the project checkpoints
and the repository's validation procedure for an applied commit ZIP.
