# Snapshot packaging

`eui-package.ps1` is the shared Windows PowerShell 5.1 preparation helper.
The normal installer and portable adapters call `New-EuiPackage` with an empty,
disjoint staging directory and an explicit policy target. It reads only the
downloaded snapshot's `.pkgmeta` and `.tools/toc_policy.json`; it never executes
downloaded code or rewrites published TOCs. No Git or Python is needed by the
portable installers. Python is used only for maintenance/audit/build tooling.

Supported `.pkgmeta` syntax is deliberately strict: unquoted literal relative
paths; `package-as: EllesmereUI`; block `ignore`; block `move-folders` from
`EllesmereUI/<source>` to unique top-level addon folders; block `externals`
containing `url`, `tag`, `branch`, `type`; and `enable-nolib-creation: no`.
Blank lines and full-line/trailing comments are accepted. Duplicate declarations,
YAML aliases, quoted scalars, flow structures, globs and unknown directives fail
closed. Ignore rules match the exact source-relative path and descendants through
`/`, never partial names. Ordering is not semantic. This is not a general YAML
parser or a claim of complete BigWigs Packager equivalence.

The copy uses robocopy `/E /MT:16`, absolute exclusion paths and same-volume
folder moves in staging. Root loose runtime files become the core; the historical
duplicate `EllesmereUI/` source directory is excluded to prevent stale overwrites.
Repository metadata is omitted even when not listed in ignore. All snapshot TOCs,
including ignored/embedded manifests, must be classified and compatible first.
Final top-level TOCs must reference existing payload files. The helper retains
vendored libraries, including embedded TOCs, and requires declared nonignored
external directories to exist. It does not resolve external URLs or versions.
BigWigs may download different external content, substitute version/debug tokens
and perform other transformations; those are outside this preparation contract.
Existing caller normalization changes text newlines to CRLF while preserving BOM
and binary bytes. Direct installation and export use that same normalized payload.

## Adding a module

Add its TOC/runtime assets to the branch, classify every TOC in
`.tools/toc_policy.json` with a loading rationale, and add the appropriate
`EllesmereUI/<module>: <module>` move when it is a separate addon. An ignore entry
holds it back independently of compatibility. No installer name list is required.
Never classify a library's nested TOC as a top-level addon merely to distribute it.
Missing/unknown manifests and missing mappings fail closed. Run TOC policy,
packaging and install safety tests before publication. Future module delivery
templates should request these three pieces: runtime tree, TOC classification,
and explicit distribution mapping/hold-back decision. External testing workflows
and ChatGPT delivery documents are unchanged by this work.

## Integration audit

`audit_pkgmeta.py` calls the same parser through `read-pkgmeta.ps1`. Supply a
validated absolute native Git path, destination and the frozen incoming SHA.
Retail uses only its eligible release SHA; PTR uses full Retail. The gate uses
Git's merge base and merge-tree candidate in a disposable object store, or the
incoming tree for fast-forward. It does not merge, edit refs, stage or resolve
conflicts. It reports semantic additions/removals/modifications and distribution
effects, protects fork differences and runtime paths, and blocks uncertain touched
or explicitly retained ignore removals. Identical inherited rules cannot encode
an unrecorded human intention: consult history/decisions and use --retain-ignore.
Unsupported layouts and textual conflicts block rather than infer a resolution.
Exit 0 is safe/no-op/unchanged, 3 requires a human decision, 1 is an error.
Use --report with a new path outside the checkout, then --verify-report after
integration to compare the actual file's SHA-256 with the audited candidate
(normalizing UTF-8 BOM and CRLF checkout conversion for this comparison only).
The update skill retains the existing merge/release/approval checkpoints.
Each historical version uses its own TOC policy when present. For upstream/base
trees without fork tooling, the report identifies reuse of the previous fork's
explicit classifications. Unknown manifests still fail, even inside `Libs/`.
The proposed tree must retain the central policy; embedded manifests are excluded
from standalone-addon layout checks regardless of their directory name.

## Portable artifacts

Build from the supplied original ZIPs, outside the checkout:

```text
<python> -B .tools/build_portable_installers.py --input <retail-original.zip> --output <new-retail.zip>
<python> -B .tools/build_portable_installers.py --input <ptr-original.zip> --output <new-ptr.zip> --ptr
```

The builder preserves menus, paths, download strategy, record formats/fingerprint
algorithms and installation routines. It replaces only preparation boundaries,
bundles maintained helpers and strengthens exported ZIP validation with file
counts, paths, sizes and SHA-256. Existing outputs cannot be overwritten.
Historical `Installable ZIP/` exports are omitted from new portable bundles;
the input archives are untouched and new exports use the shared preparation.
PrepareOnly requires a new output directory to prevent stale payload merges.
`--refresh` updates bundled helpers in a previously generated bundle after
checking its adapter target and exporter validation markers; it never reapplies
the original-source transformation or overwrites its input.
Portable validation accepts only the selected branch root, an EllesmereUI root
with a full commit SHA, or a hellsy55-EllesmereUI API root with a hexadecimal
commit suffix. Extraction must produce exactly the approved root. The original
repository installer's default archive rule is unchanged. All path, collision
and link checks remain shared. Portable write probes run after snapshot/payload
validation and normalization, immediately before the transaction; elevation
reuses and revalidates the parent's downloaded archive without another download.

Repository safety records remain version 2 with destination locks and recovery
journals. Portable records remain version 1 in their original separate state
directories, using their original transaction implementation. Bundling the repo
safety helper for path/archive/payload checks does not migrate portable records
or grant them repository locking/pending-recovery behavior. No automatic migration
is performed. The incremental Addon Update Script is outside this pipeline.

## Validation

Run `.tools/tests/test_install_policy.ps1`, `test_package_policy.ps1`,
`test_pkgmeta_audit.py`, and the existing `test_toc_policy.py` with the frozen
runtimes. `test_portable_packages.ps1` accepts extracted portable directories,
snapshot source directories and their PrepareOnly outputs; it compares source
preparation, export and Retail/PTR/XPTR fixture installation by paths, sizes and
SHA-256. It imports exporter functions without executing network/export main.
All install destinations are disposable fixtures. These tests do not certify
in-game behavior, remote downloads, UAC interaction or BigWigs equivalence.
`test_portable_edges.ps1` additionally simulates primary/API HTTP sources and
executes portable main control flow against disposable destinations, including
download/validation failures, denied probes and successful transactions. HTTP
creation and elevation are substituted only in the test harness; it never uses
a real network download, UAC prompt or WoW destination.
