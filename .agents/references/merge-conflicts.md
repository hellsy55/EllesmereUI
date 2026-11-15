# Merge conflicts

Stop at a real merge conflict. Never resolve it on your own. Inspect the necessary source internally. If the conflict is nontrivial, spans modules, or threatens fork customizations, request exactly one project `deep_reviewer` for a read-only assessment when that assessment is likely to improve the recommendation; wait for its result. Handle straightforward conflicts in the main chat. Explain the functional difference in Portuguese using: `Conflito em`, `Upstream`, `Local`, `Impacto`, `Interacao`, and `Recomendacao`. Describe the behavior lost under each choice and whether the features share a function or flow. Do not show source, diff, hunks, conflict markers, or file blocks by default. If the user explicitly requests code or a diff, show only the necessary excerpt.

Offer exactly these choices, naming the actual branches:

a) Upstream: keep the incoming version (the frozen upstream release SHA for Retail in Sync A, full `upstream/main` for the `main` mirror, or `new-features` in Sync B).
b) Local: keep the current branch version (`main` or `new-features` in Sync A, or `12.1.7-PTR-features` in Sync B).
c) Combine: propose a concrete combination when technically feasible.
d) Abort: abort the merge; nothing is applied to that branch.

### After the user chooses

A Combine choice authorizes resolving every conflict in that integration, including semantic adaptations necessary to preserve fork behavior and incorporate compatible incoming changes. Apply explicit per-feature exceptions as instructed. Treat file groups and internal review batches as progress, and continue in the same task without another continuation command. Ask for a decision only when a material functional ambiguity, an unauthorized risk, or an unsafe or irreconcilable outcome prevents proceeding. Preserve the unresolved state and report the precise technical blocker and pending work if a real execution limit prevents completion.

For a), b), or c), finish the authorized resolution, stage the intended paths and verify that native `git ls-files -u` succeeds and returns no entries. Review the integrated behavior and run the applicable packaging, manifest and technical checks. Present the required staged views, complete diff, summary, and exact proposed English commit message. Wait for explicit approval at the commit checkpoint and publish only to the named destination when authorized. An earlier conflict choice does not approve either operation.

Mark exactly one option label with `(recommended)` at its end, based on preserving useful behavior with the fewest lost changes. Wait for the user's choice. For d), run `git merge --abort` and report that nothing changed on that branch. If `main` is unexpectedly divergent, use this procedure against `upstream/main` before proceeding with Retail.
