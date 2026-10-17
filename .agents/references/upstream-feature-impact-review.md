# Upstream Feature Impact Review

Use this reference only for an incoming delta in [eui-update](../skills/eui-update/SKILL.md). It supplements integration decisions, not release selection or authorization. Keep reports and questions in Portuguese. Maintain evidence in the current execution context; do not create persistent caches or a mandatory feature inventory.

## Scope and evidence

Reuse the frozen release SHA, ancestry, merge base, incoming count and changed paths already collected by the update. For Sync A, the only eligible upstream range is `base..<release_target>`; identify the previously incorporated upstream state from ancestry, not merely a TOC version or the latest merge subject. Distinguish already incorporated commits from genuinely incoming changes. Post-release commits are excluded from implementation and recommendations for this update. Never change the release helper's subject-based selection, use a tag as a fallback, or use `main` as a bridge into Retail.

Consult official [patch notes](https://ellesmereui.com/patch-notes), [GitHub Releases](https://github.com/EllesmereGaming/EllesmereUI/releases), and relevant upstream commits, PRs and source. Cover all relevant intermediate versions between the incorporated state and the target, not only the latest notes. Map notes or release tags to the frozen Git interval; if mapping is uncertain, label it and rely on eligible code. Inspect fork history and actual implementations to establish custom behavior. Notes describe declared intent; code must confirm behavior. Missing notes do not establish unchanged behavior. If the site, Releases or PR metadata is unavailable, record the specific coverage limitation and continue using available Git evidence; do not automatically block or manufacture author intent.

Read upstream code at the frozen eligible commits, not a mutable default-branch view. Filter notes and PR discussions to changes included by that SHA; later fixes, statements or code must not support this update's behavioral conclusions or enter its integration.

## Stage A: lightweight analysis

1. Run only when an eligible incoming delta exists. Reuse path/name-status summaries; inspect targeted history and diffs instead of opening whole files or full repository diffs. Compare upstream changes with fork-side changes since the merge base. Use current branch-versus-base code and targeted commit history to distinguish customizations from merges and inherited upstream work; a manual inventory is only a hint.
2. For Sync A, compare paths in `base..<release_target>` with fork-side changed paths since `base`; for Sync B, compare incoming Retail paths with PTR-only changed paths since their merge base. When files or modules overlap, inspect the relevant diff and surrounding functions for custom features in the same function, flow or functional region, including interference without textual conflicts. This targeted inspection is mandatory for reasonable overlap; it does not require a repository-wide Stage B. Include shared APIs, callers, defaults, saved settings, events and cross-module dependencies where a changed contract can affect another path. Absence of file overlap or textual conflicts alone does not prove functional compatibility. Expand only when a concrete behavior or dependency gives a reason.
3. If there is no relevant signal, report a short conclusion with the inspected scope and material source limitations, then continue normally without a new decision checkpoint. Do not claim exhaustive runtime compatibility.
4. Escalate concrete signals only: native upstream coverage of a fork feature/fix, intentional removal supported by evidence, changed architecture or API contracts, required adaptation, or possible silent regression. Record which feature and evidence justify deeper work.

## Stage B: conditional feature review

Inspect only the implicated modules, functions and dependencies. Compare the observable fork behavior with the eligible official implementation: coverage, settings/defaults, edge cases, client differences, combat restrictions, data migration and regression risks as applicable. Trace replacements through refactors; deleted code is not proof of deliberate feature removal. A patch-note fix is not proof that a local workaround is redundant. Confirm equivalence through code and focused validation when technically possible; identify any in-game checks still needed.

Request exactly one read-only `deep_reviewer` when a complex overlap could change a consequential recommendation, as required by the previous risk triage and existing delegation criteria. This includes nontrivial conflicts or possible loss of customizations when independent review could improve the decision. Supply only the relevant evidence and wait before recommending a human choice. Keep routine status, no-op, clean non-overlapping merges and mechanical library detection in the main chat; do not review the entire repository.

For each materially affected feature, report concisely:

- Module and identifiable fork feature, with its existing behavior.
- Corresponding upstream change and verifiable evidence: full commit SHA plus path/symbol or line reference, relevant PR URL, and version-specific notes link when available. Distinguish documented intent, observed code behavior and inference.
- Objective comparison, technical rationale, regression risks, confidence and unresolved validation.
- Recommendation: preserve, modify, replace or remove, with recommended path A or B.

Path A (Combine) retains useful fork behavior and incorporates upstream changes, adapting implementation when necessary. Path B (Align with upstream) removes, replaces or modifies a specific local implementation because concrete evidence favors the official approach. Classify by the actual behavioral decision: do not label a loss or replacement of custom behavior as an A adaptation to avoid approval. Recommend the best path per feature; allow mixed decisions. With insufficient evidence, recommend provisional preservation and state what would resolve the uncertainty.

## Decision and existing checkpoints

Never automatically apply a Path B removal, replacement or modification, even during a clean merge or fast-forward. Present the concrete per-feature proposal and obtain explicit approval before the affected integration or edit can enact it. If integration itself would silently discard custom behavior, pause before it. Approval covers only the named changes; ambiguity leaves those changes pending. Offer preservation/adaptation and alignment where feasible, and allow postponement when no safe approved integration exists. Do not force an A/B decision if there is no relevant proposed change.

Reuse an existing conflict decision when it explicitly approves the same named feature outcome; do not ask the same semantic question twice. For real conflicts, retain the exact choices and procedure in [merge conflicts](merge-conflicts.md), attach the impact evidence to that report, and explain any additional Path B outcome requiring approval. A prior impact choice does not authorize resolving a later conflict. Never treat the update command, impact report or feature choice as commit approval. Full staged review and explicit approval immediately before each commit remain mandatory; library and install checkpoints remain unchanged.

## Retail, PTR and Both

Analyze Sync A's eligible upstream delta once per execution. Before Sync B, compare the full incoming Retail ref with PTR and inspect PTR-only customizations since their merge base. Reuse the upstream evidence and conclusions where behavior is identical; investigate only uncovered PTR interactions or different implementations. Retail-only features/fixes may still require this lightweight PTR check even when Sync A is a no-op; do not repeat an upstream review or query notes for an already incorporated release. Skip Sync B review when Retail is already incorporated.

Keep decisions branch-specific: a Retail alignment approval does not authorize removing a different PTR customization. Request a further decision only for a materially different outcome, stating its scope. Preserve the skill's PTR-only Retail authorization gate, branch ordering, complete Retail-to-PTR merge and installation/library scopes.

## Sharing the instructions

Maintain this reference and the skill together as tracked fork workflow files on `new-features`; propagate them to PTR through the normal approved Sync B. Never add fork workflow commits to the mirrored `main` or amend the external Cloud Launcher. Cloud must check out a fork branch containing both files and load its repository `AGENTS.md` and skill. A Cloud checkout of mirrored `main` cannot be assumed to contain these instructions; report that setup limitation rather than changing `main`. Publishing or propagating these files still requires the normal commit/push and branch authorization.
