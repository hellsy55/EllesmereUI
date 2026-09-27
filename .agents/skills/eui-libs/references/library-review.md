# Review pending library updates

For each pending update, report in Portuguese the library name, current version on this branch (or explicitly that it has never been vendored on this branch), new version found, and what changed between them. For GitHub libraries, review release notes, a changelog, or the commit log between old and new tags or commits (for example, `git log <old>..<new> --oneline` in a temporary clone). For SVN libraries, use `svn log -r <old_rev>:<new_rev> <url>` as an approximation. If no prior version is recorded, explicitly state this is the first vendoring on the branch; do not invent a diff against an absent version.

After reviewing available evidence, say whether each update appears relevant, low-risk, risky, or unclear for this addon, and explain the practical reason in Portuguese. If the evidence leaves a materially uncertain impact, request one project `deep_reviewer` for read-only analysis only when it could change the recommendation; wait for it before offering choices. Do not delegate routine, clearly low-risk updates or checks with no pending updates. Offer:

a) Update all pending libraries now.
b) Choose library by library.
c) Skip the library check this time and continue the normal flow.

Mark exactly one option label with `(recommended)` at the end. Recommend a) when all are clearly useful and low-risk, b) when relevance or risk varies, and c) when evidence is unavailable, unclear, or shows meaningful risk without a clear addon benefit. Wait for the user's choice before applying anything.
