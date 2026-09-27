# Merge conflicts

Stop at a real merge conflict. Never resolve it on your own. If the conflict is nontrivial, spans modules, or threatens fork customizations, request one project `deep_reviewer` for a read-only assessment when that assessment is likely to improve the recommendation; wait for its result. Handle straightforward conflicts in the main chat. For each conflicting section, first explain in Portuguese and plain words what each side changed and the practical effect. Then show the conflicting code from each file with Git conflict markers as a technical reference.

Offer exactly these choices, naming the actual branches:

a) Keep the incoming version (`upstream/main` in Sync A or `12.1-new-features` in Sync B).
b) Keep the local branch version (`main` or `12.1-new-features` in Sync A, or `12.1.5-PTR-features` in Sync B).
c) Combine both; propose a concrete combination when technically feasible.
d) Abort the merge with `git merge --abort`; nothing is applied to that branch.

Mark exactly one option label with `(recommended)` at its end, based on preserving useful behavior with the fewest lost changes. Wait for the user's choice. For a), b), or c), apply only that choice, `git add`, show the required staged review, commit with the required English message and no AI signature, and push `origin <matching branch>`. For d), run `git merge --abort` and report that nothing changed on that branch. If `main` is unexpectedly divergent, use this procedure against `upstream/main` before proceeding with Retail.
