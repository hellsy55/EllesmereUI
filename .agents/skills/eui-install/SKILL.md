---
name: eui-install
description: Present the EUI update install menu and run only the user-selected Retail, PTR, or Both installation stage.
---

# EUI install checkpoint

After the required syncs and library checks, stop and present one menu. Word option a) in Portuguese to run the Retail update now, the PTR update now, or the Retail + PTR update now, matching the selected mode. Option b) says in Portuguese to do nothing and stop here. Wait for the user's choice. Choosing a) itself confirms the install; do not ask again. Choosing b) ends the workflow without installing or fixing line endings.

The addon installation requires the local Windows environment and its existing WoW folders and operational scripts. Preserve the same menu in Cloud/Linux. If a) is selected there, report this local requirement and stop; do not run Windows commands, create replacement install paths, or install tooling in Cloud. Repository sync still uses the same update commands on either platform.

Only after a) is chosen, read [install commands](references/install-commands.md). Run the matching install directly in the current Codex session. After it completes successfully, run the matching line-ending fix directly in the same session. Never touch the Retail install folder in PTR mode. If UAC appears despite the session's usual administrator rights, tell the user to approve it manually and wait for confirmation before proceeding.

Handle the menu and authorized installation in the main chat. Do not request a subagent for routine execution.
