---
name: eui-update
description: Run the EUI Retail, PTR, or Both update workflow for ordinary update/atualizar commands.
---

# EUI update

Follow the mode routed from `AGENTS.md`: Retail runs Sync A; PTR runs Sync A then Sync B; Both runs Sync A then Sync B. Keep branch, install, and triggered library scopes separate. Account for uncommitted changes before switching branches. Verify that `upstream` points to `https://github.com/EllesmereGaming/EllesmereUI.git` and `origin` to the user's fork; add a missing `upstream` and verify it before continuing.

For PTR-only requests, retain the Sync A prerequisite but do not infer authorization to update Retail. Establish read-only whether Sync A would change Retail (including fast-forward from origin or publication). If so and that scope is not already explicitly authorized in the current conversation, explain the prerequisite and request explicit authorization before mutation; pause until authorized. Reuse existing authorization without asking again. If Retail needs no change, continue normally to Sync B. Do not silently skip required Retail synchronization or merge upstream directly into PTR. Retail and Both requests authorize their normal synchronization scopes; all existing human checkpoints still apply.

## Compact preflight and fetch

At workflow entry, initialize or reuse the root and environment in the shared [maintenance context](../../references/python-runtime.md). Resolve and freeze `python_runtime` before the first mutation or Python helper, whichever comes first; discover optional capabilities only when needed and cache them. Preflight failure ends the workflow before any branch changes or install checkpoint. All Python helpers below use its frozen `python_runtime`, including any accepted library stage; do not repeat environment, root, runtime, or capability discovery between stages or branches.

Use `git status --porcelain=v1 -uall` once before mutations, `git branch --show-current`, and `git rev-parse` for relevant refs. Preserve preexisting changes. Fetch upstream once per execution, quietly; fetch origin in the same invocation when possible (`git fetch --quiet --multiple upstream origin`). Reuse fetched refs. Do not print fetch progress or raw command output unless an error needs explanation. Refresh status only after an operation that could change the working tree. Use `git merge-base --is-ancestor`, `git rev-list --count`, and `git diff --name-only` or `--name-status` rather than a full log or diff for initial decisions.

Before any checkout or merge, compare ancestry. If the planned sync needs a new merge commit or manifest correction commit, resolve and freeze `lua_runtime` through the shared maintenance context before the first branch mutation of that execution. Read-only checks establish this need; inspect incoming manifests in an isolated copy with the explicit destination when a fast-forward is possible. A clean fast-forward skips compiler discovery only if destination manifest validation also passes. Reuse the pinned compiler for guardrails before each approved commit. If the source is already an ancestor of the destination, skip the merge, but still perform the manifest checkpoint below. Do not run a merge merely to get `Already up to date`. If refs diverge unexpectedly, stop for the applicable human conflict/branch decision; never overwrite commits. Report `main` before Retail, even for a no-op.

After the single successful fetch, retain a compact per-sync record: source/destination refs and SHAs, ancestry, and incoming count. Only if incoming exists, add the merge base, changed paths/name-status, and overlap yes/no. `merge-base --is-ancestor` exit 0 proves ancestry, exit 1 means non-ancestry, and any other exit is an error; missing refs, failed fetches, and failed comparisons must never become no-op results. A no-op skips full integration diffs, semantic review, merge, and sync commits, but still validates manifests before publication and proceeds to the mode's remaining stages and checkpoints. A manifest repair follows the controlled correction path below. Refresh only facts affected by an actual mutation; do not fetch again without a specific reason that invalidates the snapshot.

## Sync A: Retail from upstream

Immediately after fetch, before modifying any branch (including `main` or fast-forwarding Retail from origin), run `<python_runtime> .tools/release_target.py`. Read its JSON and freeze `release_target` to the returned full `release_target` SHA for this execution. The helper scans fetched `upstream/main` in topological order and selects the first commit whose subject begins with the case-insensitive word `release` (the project's subjects are `Release v<version>`). It checks subjects only, not commit bodies or tags, and verifies ancestry. On failure or no identifiable release, stop before any branch mutation, explain the error, and never fall back to upstream HEAD or a tag. Use the same frozen SHA in every Retail upstream decision, incoming range, merge, risk review, and library classification.

Report the latest release subject and short SHA, and the helper's count of post-release commits intentionally excluded, in Portuguese. Excluded commits do not mean an upstream update is available. `main` still mirrors full `upstream/main` below; its updates never imply a Retail update.

`main` mirrors `upstream/main`; never use `main` as a bridge to Retail. If `main` is behind `upstream/main`, check out `main`, fast-forward only, and push `origin main` only when the remote needs it. Check `origin/main` ancestry before pushing and stop on unexpected remote divergence. If local `main` diverges from upstream, stop and read [merge conflicts](../../references/merge-conflicts.md) before any resolution.

For `new-features`, first compare the local ref with fetched `origin/new-features`. Before fast-forwarding from origin, check whether `git rev-list new-features..origin/new-features` contains any SHA from `git rev-list <release_target>..upstream/main`; if so, stop for a human branch decision rather than automatically importing excluded upstream commits through origin. Fast-forward a behind local ref otherwise; stop on divergence for a human choice. Preserve existing Retail commits, including fork features/fixes after the release; do not reset or rewrite the branch to the release SHA. Before merging, record `base = git merge-base new-features <release_target>` and the exact incoming upstream range `base..<release_target>`. Count incoming commits with `git rev-list --count new-features..<release_target>`. Use `git merge-base --is-ancestor <release_target> new-features` for already-current status. If the release is already an ancestor of Retail, skip the upstream merge, create no upstream sync commit, and report that Retail is already current with the latest upstream release; still run the manifest checkpoint. Otherwise check out Retail, fast-forward to the release SHA if possible, or use `git merge --no-commit <release_target>` when a merge commit is required. Run the manifest checkpoint before staged review and the approved commit. Stop on a real conflict and read [merge conflicts](../../references/merge-conflicts.md); never resolve before the user's choice. Push Retail only after the checkpoint, and only if its ref changed or its remote is behind. Never merge `upstream/main` HEAD into Retail or use its ahead/behind counts to declare a Retail update available.

## Sync B: PTR from Retail

Compare `12.1.7-PTR-features` with fetched `origin/12.1.7-PTR-features`; fast-forward a behind local ref and stop on divergence. If Retail is already an ancestor of PTR, skip the merge but still run the manifest checkpoint. Otherwise check out PTR, fast-forward if possible, or merge Retail with `--no-commit`. Run the manifest checkpoint for PTR on the integrated tree before staged review and the approved commit; Retail Interface values must not survive this checkpoint. On conflict, stop and read [merge conflicts](../../references/merge-conflicts.md), using Retail as incoming. Push PTR only after the checkpoint, and only if its ref changed or its remote is behind. PTR mode never touches the Retail install folder or performs a Retail library check.

Always compare and merge the full `new-features` ref into PTR, never the upstream release SHA. In PTR and Both modes, continue to Sync B even when Sync A has no new release or is a Retail no-op: Retail-only features/fixes still propagate normally. The release limit applies only to upstream entering Retail.

## Packaging integration gate (before any incoming branch mutation)

Before each eligible integration or fast-forward, including from fetched origin,
run the read-only gate with the frozen native Git executable and Python runtime:

```text
<python_runtime> -B .tools/audit_pkgmeta.py --git <absolute-native-git> --destination <destination-ref> --source <frozen-incoming-sha> --report <new-report-outside-checkout>
```

For Sync A, incoming is exclusively the frozen eligible release SHA; never use
mirrored main or post-release HEAD. For Sync B, incoming is full new-features.
Run before checkout/fast-forward/merge of the affected destination. The gate
skips no-op and unchanged incoming .pkgmeta without an extensive analysis. It
uses the common merge base, previous fork, incoming and Git's proposed tree;
merge-tree writes only to a temporary isolated object store, never branch refs,
index or checkout. It does not replace or perform the existing git merge.

Exit 0 permits the existing integration; exit 3 requires a human distribution
decision before mutation; any other nonzero exit blocks integration. A textual
conflict retains the existing conflict checkpoint. Never resolve it in this gate.
Freeze both input SHAs with the report; rerun if either changes. Do not add merge
commits to safe fast-forwards. Unsupported .pkgmeta syntax fails closed.

When .pkgmeta changes semantically, translate the compact report into Portuguese:
incoming ignore additions/removals; fork customizations preserved/lost; changes
to move-folders, externals and other supported settings; modules entering/leaving
distribution and pending risks. Order-only changes are not functional changes.
No report is needed for no-op or unchanged .pkgmeta. Show the textual .pkgmeta
diff alongside semantic evidence when a choice is required. Never union ignores
or replace the fork file wholesale with incoming. An inherited removed ignore
normally stays removed; independent fork entries and mappings remain intact.

The four contents cannot prove an identical rule was intentionally retained.
Consult recorded human decisions and the fork's .pkgmeta history for removals;
pass each explicitly retained rule through --retain-ignore <literal-path>.
The gate also flags removals touched in fork-only history as uncertain. For any
uncertain provenance, customization loss or incoming exclusion overlapping fork
manifests, present the exact alternatives and distribution effects and wait for
the user's choice even when Git has no textual conflict. Independent safe
changes need no extra approval. After integration verify the resulting .pkgmeta
against the audited candidate with
`<python_runtime> -B .tools/audit_pkgmeta.py --verify-report <saved-report>`
before the manifest/staged review checkpoints (only when the report has a
proposed candidate; unchanged/no-op reports need no verification);
any difference requires renewed semantic review. All existing merge, release,
library, publication and commit approvals remain in force.

## Manifest checkpoint (Retail and PTR, including no-op)

Use the single policy in `.tools/toc_policy.json` and the commands documented in
[TOC compatibility](../../references/toc-compatibility.md). Never apply this fork
policy to `main`, change release selection, or normalize an unresolved index.
After a successful integration (including a fast-forward from origin), or after
the user's approved conflict resolution leaves no unmerged paths, run:

```text
<python_runtime> -B .tools/normalize_tocs.py fix --target <destination-branch>
<python_runtime> -B .tools/normalize_tocs.py check --target <destination-branch>
<python_runtime> -B .tools/tests/test_toc_policy.py
<python_runtime> -B .tools/guardrails.py
git diff --check
```

Use `new-features` for Sync A and `12.1.7-PTR-features` for Sync B. Do not infer
the target from Interface values. Classify unknown manifests explicitly after
examining their loading behavior; duplicated headers, conflicting client metadata,
or unknown manifests stop the checkpoint without automatic repair.

On a source-ancestry no-op, first run `check` against the destination tree, using
an isolated copy and `--root` if it is not checked out. No drift means no edits or
commit. With drift, report the correction, resolve the compiler before mutation,
then check out that destination safely and follow `fix`, `check`, tests and
guardrails above. For PTR-only requests this does not grant permission to repair
Retail: retain the existing Sync A authorization check.

Stage only intended integrated/corrected files. Show all four required staged
views, including the complete native diff, and wait for explicit approval
immediately before every commit. Include normalization in an already pending
merge commit; a fast-forward or no-op needing repair requires one approved
correction commit. Do not publish, install, or begin the dependent Sync B while
the correction is uncommitted or validation fails. After any accepted library
stage, recheck manifests before its final review and publication. Finish with a
second `fix` that reports zero changes and a successful `check`.

## Upstream Feature Impact Review

Before the incoming integration described in Sync A or Sync B (including a fast-forward), use the compact sync record for Stage A of the [impact review](../../references/upstream-feature-impact-review.md). Load that reference only when an eligible incoming delta exists. This replaces targeted risk triage rather than adding a second semantic review. No-op skips it. Review functional interactions even without Git conflicts; escalate only concrete impact signals to Stage B. Reuse Retail evidence in PTR and Both; investigate only uncovered PTR differences. Report no relevant impact briefly and continue without an A/B choice. Any required impact decision precedes the affected integration; it never replaces conflict choices, complete staged review, commit approval, library approval, or the install menu.

## Mode sequence and checkpoints

- Retail: Sync A, then the Retail install menu.
- PTR: Sync A, then Sync B, then the PTR install menu. Sync A must not cause a Retail install, Retail library update, or any touch to the Retail install folder.
- Both: Sync A, then Sync B, then one install menu for Retail + PTR.

## Event-driven external libraries

Ordinary updates do not load `eui-libs`, run the external version checker, ask about libraries, or mention them in the report. A clear user request to check libraries or update with libraries triggers the normal branch-scoped [eui-libs](../eui-libs/SKILL.md) stage after sync.

The other trigger is an upstream change in the exact incoming range recorded before Sync A. Run `<python_runtime> .tools/classify_library_range.py <base> <release_target>` only when Sync A has incoming commits. Post-release upstream changes and an already-incorporated release never trigger this check. This local-only command summarizes affected libraries using `.pkgmeta` externals, library directories, and library metadata; it does not query releases or vendor files. If it reports no library changes, continue silently. If it reports changes, summarize only the added, modified, or removed libraries and ask exactly: `O upstream alterou libraries. Deseja verificar se há atualizações nas demais libraries? a) Sim b) Não`. Do not load `eui-libs` or run the checker until the user chooses a). If the user chooses b), continue without claiming the other libraries are current; when needed, say only `Demais libraries: não verificadas`. In Both mode, an accepted check applies to Retail after Sync A and PTR after Sync B, with separate reports, lockfiles, approvals, and commits.

At the install stage, read [eui-install](../eui-install/SKILL.md). Preserve its exact menu and authorization even after a no-op or resolved conflict. Report in a few Portuguese progress lines: preflight scope and clean/dirty state; release target, incoming release commit count, excluded post-release count, and only branches that changed; then the install checkpoint. Surface errors, conflicts, feature risks, and required choices. Keep hashes other than the release summary, full status, fetch output, checkout output, temporary paths, copied-file lists, and line-ending details out of routine output. Report line-ending fix scope only if relevant.

Installation policy changes remain centralized in `.tools/install/` and propagate from Retail to PTR through Sync B. Records remain independent per AddOns destination; branch sync never deletes installed folders. The install skill owns the shared transaction and fingerprint cleanup rules. Installation backups are temporary recovery data: remove only the current operation's backups after success or verified complete rollback, preserve incomplete recovery and preexisting backups, and report cleanup failures.
