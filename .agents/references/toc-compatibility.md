# TOC compatibility maintenance

`.tools/toc_policy.json` is the only classification and Interface configuration.
It currently maps `new-features` to `120105`, `12.1.7-PTR-features` to `120107`,
and Camelot to `16001`. Update these explicit values when a patch is approved;
the tool never guesses future versions. New branches require explicit entries.

## Source trees

Use the Python resolved by the shared maintenance preflight:

```text
<python_runtime> -B .tools/normalize_tocs.py check --target new-features
<python_runtime> -B .tools/normalize_tocs.py fix --target new-features
<python_runtime> -B .tools/normalize_tocs.py check --target 12.1.7-PTR-features
<python_runtime> -B .tools/normalize_tocs.py fix --target 12.1.7-PTR-features
```

`--root <isolated-copy>` supports sandboxes and detached HEAD without a branch
lookup. `--policy <path>` supports isolated fixtures; normal maintenance uses the
committed policy next to the tool. Exit 0 means success, exit 1 means a validation
or I/O failure, and argparse uses exit 2 for invalid command syntax.

Discovery includes nested and untracked `.toc` files, case-insensitively, including
ignored library folders. Only root `.git`, `.release` and `.pkgmeta-cache` trees
are excluded as Git metadata, build output and downloaded library cache. Symlinks
are rejected. All classified source manifests must exist. Unknown manifests fail
both modes before any write; review their real loading behavior and classify them.

Retail and Camelot classes control Interface and AllowLoadGameType. Shared addons
retain both Interfaces and cannot silently acquire a client restriction. Conflicting
ExcludeLoadGameType, duplicated metadata, client-specific Interface overrides,
conflict markers and an unmerged Git index fail closed. Review these conditions;
the tool is not a merge-conflict resolver. Embedded library manifests retain their
vendor Interface values: their nested TOCs do not control the suite's explicit Lua
loads. This does not certify standalone library compatibility on either client.

The fixer plans all changes before writing, preserves UTF-8 BOM and each existing
line ending, and changes only the two managed headers. Missing managed headers
are inserted. Unrelated bytes (Lua paths, comments, held-back metadata, saved data
and dependencies) stay intact. Each changed file is atomically replaced using a
temporary sibling. An I/O failure during a multi-file operation can leave earlier
complete replacements in place; inspect the reported changes and rerun check.
There is no write, temporary file or timestamp change for an already correct file.

Run `.tools/tests/test_toc_policy.py`, the maintenance tests and guardrails with
the pinned Python/Lua runtimes before commit. `eui-update` owns the integration,
conflict and full staged-review checkpoints; this tool grants no commit approval.

## CI and releases

`toc-policy.yml` checks branch pushes and PRs targeting the two maintained branches.
It selects PR base from the event payload, and the full branch ref on push. It
never fixes files. `main` is excluded and remains an upstream mirror.

No repository mechanism previously created release tags; the old workflow only
responded to pushed tags. The helper now automates future annotated local tags:

```text
<python_runtime> -B .tools/release_manifest.py tag --target new-features --tag <existing-tag-naming-convention>
<python_runtime> -B .tools/release_manifest.py tag --target new-features --tag <existing-tag-naming-convention> --create
```

The first command is a dry run. The second, only when separately authorized,
creates an annotated tag on the clean, validated destination branch, with one
`EUI-Target: <branch>` line. It never overwrites a tag or pushes. PTR uses its exact
branch name. Tag names are unchanged; historical tags/releases are untouched.

Publication requires an annotated tag, one known target, the tag's commit equal
to HEAD, and ancestry in fetched `origin/<target>`. The source manifests must
match that target and the checkout must be clean. A tag on the wrong client
content fails even when that commit is an ancestor of both maintained branches.
Full history/remote refs are required; unavailable refs fail rather than guessing.

Local `.tools/release.sh` / `.tools/release.bat` build without upload. They accept
`--target <branch>` for detached copies, or `--tag <name>` to validate a local tag.
An active known branch can supply the default only for local builds. Set
`EUI_PYTHON` to the maintenance interpreter where `python3` is not usable. Raw
packager flags are rejected so they cannot bypass the validated tree/layout.
The CI-only publication invocation is `bash .tools/release.sh --publish --tag NAME`.
Do not invoke publication without separate authorization.

Both paths validate source before downloading/starting the packager. The wrapper
checks the complete SHA256 of its pinned script and inserts a single archive gate
at its verified publication boundary, in a temporary copy. The original packager
still builds and uploads in one execution with unchanged destinations/credentials.
Updating the packager requires reviewing the pin, checksum and boundary together.
No modified third-party script is committed. A missing/mismatched boundary fails.

Before any uploader can run, the gate requires the packager's selected tag to
match the explicitly requested tag (including when multiple tags point to HEAD).
It checks actual ZIPs using the same policy,
the literal `.pkgmeta` package name, folder moves and ignored modules. It rejects
missing/duplicate/unknown suite manifests, incompatible headers, and changed suite
manifest content apart from version substitution and BOM/newlines. Held-back
modules stay excluded by `.pkgmeta`. TOCs under declared external destinations are
reported separately, not certified: packager downloads may differ from checked-in
libraries. Nested non-external libraries keep their explicit classification.

Protection applies to commits containing this workflow. Tags on older commits or
the upstream-mirroring `main` can execute their historical, unprotected workflow.
Universal enforcement would require separate repository rules outside this change.
Static tests and ZIP fixtures do not establish in-game functionality or validate
network publication credentials/services.
