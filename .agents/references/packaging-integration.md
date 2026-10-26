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
