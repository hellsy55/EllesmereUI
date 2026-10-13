# EUI agent instructions

This repository is a fork of https://github.com/EllesmereGaming/EllesmereUI.

## Always-on rules

- Speak to the user in Portuguese, including explanations, summaries, choices, and conflict reports.
- Write everything stored in files or on GitHub in English, including code comments, documentation, commit subjects and bodies, merge messages, PR descriptions, tags, and Git-generated text.
- Commit under the user's name, with only the intended message. Never add AI signatures such as `Co-Authored-By: Codex` or `Generated with Codex`.
- Write each commit subject in English, imperative mood, on one line, covering all meaningful changes concisely. Use `Module (type): brief description`, with a recognizable module and an appropriate type such as `fix`, `feature`, `chore`, or `docs`. Group descriptions of the same module and type with `; `. Keep different types for one module adjacent. Separate sections with `. ` and omit a final period. This applies to sync and library commits too. Examples: `CDM (fix): guard secret spellID values. Raid Tools (feature): disable Convert to Party for raids over 5 members`; `Libraries (chore): update LibSharedMedia to <version>`.
- Before every commit, inspect the staged file list and unstage any unrelated files while preserving their worktree changes. Stage only user-facing addon changes or intentionally maintained project files. Stop and ask if anything staged is unexpected. Show the user `git diff --cached --name-only`, `git diff --cached --name-status`, a concise `git diff --cached --stat`, and the COMPLETE `git diff --cached`, with no size exception. Wait for explicit user approval immediately before `git commit`; prior approval to implement a change does not replace this approval. Apply this checkpoint to normal commits, merge commits, and library commits; do not let a merge create a commit before the checkpoint.
- Preserve preexisting and unrelated changes. Never commit local-only test scripts, scratch files, generated diagnostic helpers, or temporary tooling unless the user explicitly requests that exact file be versioned.
- For code navigation, use scoped `rg --files` and `rg -n` searches before reading whole files; start with relevant excerpts and expand as needed to understand behavior and dependencies. Keep required checks and complete staged reviews intact.
- At maintenance entry, freeze the repository root and execution environment using the shared [maintenance preflight](.agents/references/python-runtime.md). Resolve and freeze Python 3 once before the first mutation or Python helper, whichever comes first; read-only analysis without Python helpers does not require runtime resolution. Discover optional capabilities only when needed and cache their results. Reuse this context across skills and branches; load environment-specific references only when needed. If no compatible runtime is valid, stop before mutation or Python helper execution.
- Never resolve a merge conflict, apply an upstream PR, or vendor an external library without the workflow's explicit human choice. Never run an install without the install menu choice. An install menu choice of option (a) is sufficient confirmation.

## Branches and command routing

- `main` mirrors `upstream/main` on the fork and receives no direct feature commits.
- `new-features` is Retail and syncs only through the most recent commit in `upstream/main` whose SUBJECT starts with `release`, case-insensitive. Exclude all later upstream commits. If that release commit cannot be identified, stop the workflow; never fall back to `upstream/main` HEAD or a tag.
- `12.1.5-PTR-features` is PTR and receives Retail changes by merging `new-features`, after Retail is synced.
- For `update`, `atualizar`, `update retail`, `atualizar retail`, `atualizar o retail`, and close case-insensitive variants, use [eui-update](.agents/skills/eui-update/SKILL.md) in Retail mode.
- For `update PTR`, `atualizar PTR`, and close case-insensitive variants, use [eui-update](.agents/skills/eui-update/SKILL.md) in PTR mode.
- For `update both`, `atualizar ambos`, and close case-insensitive variants, use [eui-update](.agents/skills/eui-update/SKILL.md) in Both mode.
- These modes have different branch and install scopes. Library checks are event-driven as specified in `eui-update`; if triggered, Retail checks Retail, PTR checks PTR, and Both checks each branch separately. If the requested mode is genuinely ambiguous, ask before acting.
- For a GitHub PR URL with a request to implement, apply, port, or evaluate it, including `implement PR <link>` and `implementar PR <link>`, use [eui-implement-pr](.agents/skills/eui-implement-pr/SKILL.md). That skill validates the repository before any further action.
- During an update, load [eui-libs](.agents/skills/eui-libs/SKILL.md) for an explicit library-check request, or after an upstream library-change trigger and the user's choice to check. Load [eui-install](.agents/skills/eui-install/SKILL.md) only at the install-menu stage. Read detailed references only when that stage needs them.

## Delegation

Handle routine work in the main chat without delegation: Git status, clean merges, already-current results, script execution, library checks with no pending updates, authorized installs, and simple diffs or stats. Do not parallelize by default. Request one project `deep_reviewer` only when an independent read-only review is likely to change a consequential decision: a nontrivial conflict, large or ambiguous PR, possible loss of local customizations, multi-module change, difficult regression, or genuinely uncertain library impact. Prefer the main agent when it is sufficient; subagents consume extra tokens. Wait for the review before recommending a human choice. Never let delegation bypass a human checkpoint.

## Token Savings Reporting

At the beginning of each task, when RTK is available, capture its cumulative savings counters using the supported `rtk gain` output format. At task completion, capture the counters again and calculate the difference.

- Report estimated RTK tokens saved, the reduction percentage, and the number of RTK-optimized commands attributable to this task when the available telemetry supports that attribution.
- Use the supported RTK output format and options for the installed version. Do not assume an unsupported JSON flag or output schema.
- RTK estimates concern terminal output compression, not exact model tokens, billed usage, or total task savings.
- RTK counters may be global across repositories and sessions. Do not attribute a global difference to this task if concurrent activity makes attribution unreliable.
- If reliable task-specific measurements are unavailable, do not present global or historical RTK savings as if they were generated by this task.
- Other optimizations, including selective file reading, scoped searches, deferred skill/reference loading, caching, and reduced context, may be mentioned qualitatively but must not be assigned invented token savings.
- If actual task token usage is exposed by the execution environment, report it separately from estimated savings. Never confuse usage with savings.
- Do not rerun development commands without optimization merely to establish a comparison.
- Do not install extra tooling, change existing workflows, or perform expensive measurements solely for reporting.
- If reliable metrics are unavailable, report `Token savings: unavailable` and briefly state why. Never invent percentages or totals.
- Append a compact `Token Savings` section to the final task report, in Portuguese, distinguishing measured data, estimates, and unavailable metrics.
- When sufficient measurements exist, clearly identify the comparison baseline and the scope of the reported reduction.
- Do not claim an exact comparison against an entirely unoptimized execution unless such an equivalent baseline was actually measured.
- Do not let metric collection delay or block development, testing, approval checkpoints, ZIP delivery, or Google Drive delivery.
- Apply this reporting rule to all repository workflows, including updates, PR implementation, library checks, temporary testing, maintenance, and no-op tasks.
- Keep reporting concise and avoid unnecessary telemetry commands or verbose output.

## Technical validation and upstream contribution rules

The fork workflow above continues to govern branch routing, approvals, installation, and local customizations. Apply upstream contribution policies when preparing contributions to upstream.

Read `.github/CONTRIBUTING.md` first. It has the acceptance criteria and code style.

Run the guardrails before you commit:

```
python3 .tools/guardrails.py
```

(On Windows: `python` or `py -3`.) It checks the Lua files (`.lua` in any case, outside `Libs/` and `.tools/`) that changed since your branch left `origin/main`, uncommitted and untracked ones included. On a fork with an `upstream` remote it compares with whichever of `upstream/main` and `origin/main` the branch left more recently, and warns when that is `origin/main` while `upstream/main` lacks some of its commits: a PR to upstream is judged against `upstream/main`, so fetch `upstream` or pass `--base upstream/main`. `--base <ref>` picks another base. CI runs the same checks on every PR that touches Lua or the guardrails, and on every push to main. It needs a Lua 5.1 `luac` (`luac5.1` on PATH, or set `LUAC=/path/to/luac`). The compile and line-1 checks read every changed file; the others judge only new and changed lines, so older code is reported only once you edit it. An expired exception fails wherever it is (see Exceptions). File names must be valid UTF-8.

If you change `.tools/guardrails.py`, run its tests as well: `python3 .tools/tests/test_guardrails.py`.

### Rules and what enforces them

| Rule | Enforced by |
|---|---|
| Every Lua file compiles under Lua 5.1, with at most 200 locals in scope at once and 60 upvalues per function. One overflow stops the whole file from loading. | `guardrails.py` `check_compile` |
| Line 1 of every Lua file except `EllesmereUI_ClientGate.lua` starts with `if EUI_CLIENT_BLOCKED then return end`. | `guardrails.py` `check_client_gate` |
| Defer combat-locked work through `EllesmereUI.CombatQueue.Defer(key, fn)` (or the addon's `ns.CombatQueue`). Do not register a raw `PLAYER_REGEN_ENABLED` for it, in any form: `f:RegisterEvent`, `f.RegisterEvent(f, ...)`, `pcall`/`xpcall(f.RegisterEvent, ...)`, an event name kept in a local, an event list (or a list of `{ event = ... }` records) or a handler table keyed by event that a loop or call registers, an event appended to a list, an event helper or `EventRegistry`. A frame, list or helper that registers both `PLAYER_REGEN_DISABLED` and `PLAYER_REGEN_ENABLED` tracks combat state, which is not a deferral, and passes, also when one of the two names the frame another way: the first parameter of its script handler (a function literal given to `SetScript`/`HookScript`, or a function of the same file given to them by name), a local copy of a field that holds it, a field that a local holding it is stored in, or `self` in another `:` method of the same object in the same file. A local given a new frame (`f = CreateFrame(...)`) is a new registrant. An event list written inline in an `ipairs`/`pairs` loop header or an unregister call counts only once something registers it; any other event list counts where it is written. The check does not see an event name or handler table that reaches the registration through a field, a function's parameter or return value, or another file, nor a name built at run time; those are still against this rule. | `guardrails.py` `check_combat_deferral` |
| Do not call globals that WoW Forever lacks: the legacy spec functions (`GetSpecialization`, `GetSpecializationInfo`, `GetNumSpecializationsForClassID`, `GetActiveSpecGroup`, `GetSpecializationMasterySpells`, `GetTalentInfo`) and the item, socket, coin, PvP, pet, sound and trade globals that retail keeps only as deprecation fallbacks (`GetItemInfo`, `GetItemInfoInstant`, `GetItemCount`, `GetItemIcon` and the rest of `DEPRECATED` in `guardrails.py`). Use the `C_` form the error names (`C_SpecializationInfo.*`, `C_Item.*`, ...). `GetSpecializationInfoByID` has no `C_` form: guard it and fall through to no spec. `_G.X` counts as `X`, and so do copying `X` into a local, storing it in a table or variable, and `hooksecurefunc("X", ...)`. These pass: a local bound to the `C_` form; a test of the global (`if X then`, `X and X()`, `X ~= nil`, `type(X) == "function"`), including an early exit (`if not X then ... return end`); an `IS_FOREVER` gate (`if not IS_FOREVER then`, `IS_FOREVER ~= true`, `if IS_FOREVER then ... return end`); the `else` of a test of the `C_` form. A guard carried through a variable (`local i = X and X() or 0` ... `if i > 0`) is not seen: use the `C_` form there. Files of an addon whose TOC never loads on Forever are skipped. | `guardrails.py` `check_deprecated_globals` |
| Outside `EllesmereUILocales/`, Lua is ASCII only and saved as UTF-8 without a BOM. Use `--` or a byte escape such as `\226\128\148`. | `guardrails.py` `check_ascii` |
| After you add, change or remove a string literal passed to `EllesmereUI.L("...")` or `EllesmereUI.Lf("...")`, run `bash .tools/extract-locale-keys.sh` and commit `EllesmereUILocales/_keys.txt`. | `locale-check.yml` (PRs and pushes to main) |
| Do not compare, index, or do arithmetic on secret values (12.x combat aura and unit data). Pass them straight to the widget API that accepts them. | Judgment only. No reliable mechanical check. |
| Do not write to protected Blizzard frames or call protected functions from insecure code, and do not do it in combat. Hook with `hooksecurefunc` and keep the work cosmetic. | Judgment only. No reliable mechanical check. |

### Exceptions

Put an exception in a comment on the offending statement, naming the human who approved it and why. Any line of the statement counts (for a table, anywhere from its first line to its closing brace) except the inside of a function written in it: a tag there counts only for that function's own statements, so tag a call or table that holds a function on its first line, a key's line or its closing `end)` or `}` line. It does not expire:

```lua
local STOPWORDS = { ... } -- guardrails-allow: ascii by Ellesmere: Russian search stopwords
```

For a stopgap, add an expiry date right after the key. Once the date (UTC) has passed, every guardrails run fails on it wherever it is in the tree, so every later Lua PR fails until the tag is removed or its date moved:

```lua
local name = GetItemInfo(id) -- guardrails-allow: deprecated-global until 2026-12-31 by Ellesmere: retail-only path, C_Item port pending
```

Check keys: `combat-deferral`, `deprecated-global`, `ascii`. A tag is `guardrails-allow:`, colon included, in a comment; one in a string does not count. A tag fails when it has no approver or no reason, an unknown key, a bad date, or a date, the word `until` or another tag in the approver (between `by` and the next colon).

### Keeping this table

When a reviewer corrects a mistake, fix it and add the rule here. If the rule is already here and nothing enforces it, add a check to `.tools/guardrails.py` in the same change. Remove a rule when its mistake can no longer happen.
