# Install and line-ending commands

The maintained installer sources live in `.tools/install/`. Manual scripts in `C:\Users\jonat\Desktop\EUI` are deployed copies: update the installer, shared safety helper and line-ending fixer together. Codex runs the maintained sources directly. Both entry points retain records in `C:\Users\jonat\Desktop\EUI` to preserve legacy records. Run commands directly in the current Codex session, which normally has administrator rights. Do not use `start`, `Start-Process`, or any separate window; the direct process naturally waits for completion, so no extra detection, file checking, or window-closing handling is needed.

Repository/Codex metadata such as `AGENTS.md`, `.agents/`, and `.codex/` must not be copied into the installed addon. The operational installer excludes `AGENTS.md` through robocopy's `/XF` filter and `.agents` and `.codex` through `/XD` when copying both the core and `EllesmereUI*` modules into staging, preserving the existing exclusions.

| Mode | Install | Line-ending fix after successful install |
| --- | --- | --- |
| Retail | `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\jonat\Desktop\EUI\Github\EllesmereUI\.tools\install\atualizar-eui.ps1" -Only Retail` | `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\jonat\Desktop\EUI\Github\EllesmereUI\.tools\install\corrigir-fim-de-linha.ps1" -Only Retail` |
| PTR | `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\jonat\Desktop\EUI\Github\EllesmereUI\.tools\install\atualizar-eui.ps1" -Only PTR` | `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\jonat\Desktop\EUI\Github\EllesmereUI\.tools\install\corrigir-fim-de-linha.ps1" -Only PTR -PtrAddOnsPath "<selected PTR AddOns path>"` |
| Both | `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\jonat\Desktop\EUI\Github\EllesmereUI\.tools\install\atualizar-eui.ps1" -Only Both` | `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\jonat\Desktop\EUI\Github\EllesmereUI\.tools\install\corrigir-fim-de-linha.ps1" -Only Both -PtrAddOnsPath "<selected PTR AddOns path>"` |

The Both batch runs `atualizar-eui.ps1` without `-Only`, installing Retail from `new-features` and PTR from `12.1.7-PTR-features`, in that order, into their separate folders. The Both line-ending command fixes Retail and the selected PTR folder. Retail install folder: `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns`. Before any installation in PTR or Both mode, the installer presents `Option 1 - PTR` (`C:\Program Files (x86)\World of Warcraft\_ptr_\Interface\AddOns`) and `Option 2 - Experimental PTR` (`C:\Program Files (x86)\World of Warcraft\_xptr_\Interface\AddOns`). It requires an explicit choice, provides cancellation, validates the selected directory, and installs PTR only there. PTR downloads the ZIP of `12.1.7-PTR-features`. Replace `<selected PTR AddOns path>` in the line-ending command with the exact path selected in that successful install; the placeholder is not a literal argument. The existing line-ending fixer supports `-PtrAddOnsPath`, so it needs no code changes. Do not use `Corrigir_Fim_de_Linha.bat` for this workflow because it uses the legacy default PTR destination. Run no line-ending command when installation did not run or did not complete successfully.


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
