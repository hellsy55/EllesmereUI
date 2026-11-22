# Install and line-ending commands

The maintained installer sources live in `.tools/install/`. Manual scripts in `C:\Users\jonat\Desktop\EUI` are deployed copies: update the installer, shared safety helper and line-ending fixer together. Codex runs the maintained sources directly. Both entry points retain records in `C:\Users\jonat\Desktop\EUI` to preserve legacy records. Run commands directly in the current Codex session, which normally has administrator rights. Do not use `start`, `Start-Process`, or any separate window; the direct process naturally waits for completion, so no extra detection, file checking, or window-closing handling is needed.

Repository/Codex metadata such as `AGENTS.md`, `.agents/`, and `.codex/` must not be copied into the installed addon. The operational installer uses `eui-package.ps1` beside the safety helper. Deploy all three with the line-ending fixer. The shared preparation reads `.pkgmeta` and `.tools/toc_policy.json` from the downloaded snapshot, validates manifests without rewriting them, applies literal ignore paths and folder moves, and retains vendored runtime libraries without downloading externals. Unsupported packaging syntax stops before installation. See [.tools/install/README.md](../../../../.tools/install/README.md) for supported syntax and portable packaging.

From the verified repository root, pass the active mode and the numeric choice already made in chat:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .tools/install/atualizar-eui.ps1 -Only <mode> -InstallChoice <choice>
```

| Mode | Choice 1 | Choice 2 | Choice 3 |
| --- | --- | --- | --- |
| Retail | Retail | Abort | Invalid |
| PTR | PTR | XPTR | Abort |
| Both | Retail + PTR | Retail + XPTR | Abort |

The AddOns paths are under `C:\Program Files (x86)\World of Warcraft`. Retail uses `_retail_\Interface\AddOns`, PTR uses `_ptr_\Interface\AddOns`, and XPTR uses `_xptr_\Interface\AddOns`. Retail installs from `new-features`; either PTR client installs from `12.1.7-PTR-features`. Both validates the selected PTR path before writing and runs Retail first. A valid supplied choice skips the prompt. Without a choice the standalone installer shows the menu for `-Only`, which defaults to Both. Invalid entries are retried in the same menu.

After successful installation, run the fixer with the same mode. For PTR or Both supply the exact selected path explicitly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .tools/install/corrigir-fim-de-linha.ps1 -Only Retail
powershell -NoProfile -ExecutionPolicy Bypass -File .tools/install/corrigir-fim-de-linha.ps1 -Only <PTR-or-Both> -PtrAddOnsPath "<selected PTR AddOns path>"
```

On abort Codex invokes neither script.

## Managed-folder policy

All manual and Codex installations use `Invoke-EuiInstallTransaction` from the
shared `.tools/install/eui-install-safety.ps1`. Never clean AddOns by prefix,
wildcard, creation time or a legacy names-only record. Version 2 records are keyed
by normalized destination and contain SHA-256 fingerprints of relative file
paths, contents and directories in deterministic ordinal order. Records remain
independent for Retail, PTR and Experimental PTR.

Folders in the prepared package are replaced even when locally modified. An old
managed folder missing from the package is removed only when its full current
fingerprint matches the valid previous record. Modified obsolete folders are
preserved, reported in one warning and dropped from management. Independent
folders, including `EllesmereUI_AddonSkins`, are silently preserved. Missing and
legacy records authorize no obsolete removal. Invalid records also authorize
none and produce an operational diagnostic.

The installer validates paths and the package, takes an exclusive destination
lock, journals the operation and moves replaced/removed folders into an AddOns
backup before copying. It verifies installed contents before publishing the
manifest. First publication uses `File.Move`; replacement uses `File.Replace`
with a unique absolute backup path on the same filesystem. Failed persistence
rolls back folders and retains the old record. Rollback completion is verified
against the original folder fingerprints before recovery is declared complete. Failed rollback retains its
backup and pending marker. Backups belong only to the current transaction:
a successful installation or a fully verified rollback automatically removes its
folder backup. The unique manifest backup is removed after successful publication
or verified restoration. No historical copies are retained after successful
updates. Cleanup failures produce a warning with the retained path; they do not
turn a completed installation or restoration into an incomplete recovery. Never
remove backups from other executions or pending recovery data. If removing the
transaction marker fails after completion, retain its referenced folder backup
and warn that installation or rollback completed but cleanup is pending. New
installation and repair remain blocked until that marker is inspected; do not
report incomplete rollback merely because cleanup failed. A pending marker blocks retry and line-ending repair:
inspect its destination, manifest, previous names and backup, and restore the old
folders before removing the marker. Never delete recovery data to bypass this
block. The stable `.lock` file is intentional; process termination releases its
exclusive operating-system handle.

Downloaded ZIP, extraction and staging paths are unique to each invocation;
cleanup runs on success and failure and is restricted to paths created by that
invocation. Preserve these safeguards when deploying the operational copies.
An `.incomplete` indicator left by an older backup-free installation blocks new
installation and repair for manual inspection; do not discard it automatically.

Run `powershell -NoProfile -ExecutionPolicy Bypass -File .tools/tests/test_install_policy.ps1`
for isolated fixture tests. No real World of Warcraft directory is used. Preserve
the mandatory installation menu and explicit PTR destination selection.
