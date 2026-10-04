# Merge conflicts

Stop at a real merge conflict. Never resolve it on your own. Inspect the necessary source internally. If the conflict is nontrivial, spans modules, or threatens fork customizations, request exactly one project `deep_reviewer` for a read-only assessment when that assessment is likely to improve the recommendation; wait for its result. Handle straightforward conflicts in the main chat. Explain the functional difference in Portuguese using: `Conflito em`, `Upstream`, `Local`, `Impacto`, `Interacao`, and `Recomendacao`. Describe the behavior lost under each choice and whether the features share a function or flow. Do not show source, diff, hunks, conflict markers, or file blocks by default. If the user explicitly requests code or a diff, show only the necessary excerpt.

Offer exactly these choices, naming the actual branches:

a) Upstream: keep the incoming version (`upstream/main` in Sync A or `new-features` in Sync B).
b) Local: keep the current branch version (`main` or `new-features` in Sync A, or `12.1.5-PTR-features` in Sync B).
c) Combine: propose a concrete combination when technically feasible.
d) Abort: abort the merge; nothing is applied to that branch.

Mark exactly one option label with `(recommended)` at its end, based on preserving useful behavior with the fewest lost changes. Wait for the user's choice. For a), b), or c), apply only that choice, `git add`, show the required staged review, commit with the required English message and no AI signature, and push `origin <matching branch>`. For d), run `git merge --abort` and report that nothing changed on that branch. If `main` is unexpectedly divergent, use this procedure against `upstream/main` before proceeding with Retail.
