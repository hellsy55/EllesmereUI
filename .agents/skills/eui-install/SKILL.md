---
name: eui-install
description: On confirmed local Windows, present the EUI update install menu and run only the user-selected Retail, PTR, or Both installation stage.
---

# EUI install checkpoint

Reuse the workflow's frozen root and environment. For standalone entry, initialize them once through the shared [maintenance context](../../references/python-runtime.md). Proceed only in confirmed `local_windows`. In `cloud`, skip the entire checkpoint and continue the applicable delivery and report. In `other`, skip physical installation. The update workflow does not load this skill in either environment.

After the required syncs and library checks, stop and present one menu. Word option a) in Portuguese to run the Retail update now, the PTR update now, or the Retail + PTR update now, matching the selected mode. Option b) says in Portuguese to do nothing and stop here. Wait for the user's choice. Choosing a) itself confirms the install; do not ask again. Choosing b) ends the workflow without installing or fixing line endings.

For PTR and Both, the operational installer must also prompt for exactly one PTR destination: option 1 selects `C:\Program Files (x86)\World of Warcraft\_ptr_\Interface\AddOns`; option 2 selects `C:\Program Files (x86)\World of Warcraft\_xptr_\Interface\AddOns`. There is no default; blank or invalid input must prompt again, and cancellation stops before any installation. In Both mode, select and validate the PTR destination before installing either client. Do not bypass this interactive selection or install to both PTR folders. After successful installation, pass the same selected path explicitly to the line-ending fixer; never use its default PTR path for this workflow.

The addon installation requires the existing local Windows WoW folders and operational scripts. Only after a) is chosen, determine and cache physical-install capability if not already known. If unavailable, explain the local requirement and stop without installation. In local Windows, complete Python preflight if not already resolved before installation, then read [install commands](references/install-commands.md). Run the matching install directly in the current Codex session. After it completes successfully, run the matching line-ending fix directly in the same session. Never touch the Retail install folder in PTR mode. If UAC appears despite the session's usual administrator rights, tell the user to approve it manually and wait for confirmation before proceeding.

Handle the menu and authorized installation in the main chat. Do not request a subagent for routine execution.

All authorized installations must use the shared managed-folder transaction and per-destination fingerprint policy in [install commands](references/install-commands.md). Use the maintained `.tools/install/` sources, keeping legacy record storage unchanged. Use backups only for failure recovery. Automatically remove the current operation's folder and manifest backups after success or verified complete rollback; preserve them after incomplete recovery. Warn if cleanup fails. Never delete preexisting backups, perform prefix-based cleanup or bypass pending recovery markers.
