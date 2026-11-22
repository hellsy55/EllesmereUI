---
name: eui-install
description: On confirmed local Windows, present the EUI update install menu and install only the clients allowed by the update mode, or abort.
---

# EUI install checkpoint

Reuse the workflow's frozen root and environment. For standalone entry, initialize them once through the shared [maintenance context](../../references/python-runtime.md). Proceed only in confirmed `local_windows`. In `cloud`, skip the entire checkpoint and continue the applicable delivery and report. In `other`, skip physical installation. The update workflow does not load this skill in either environment.

After sync and any library checks, present one menu titled **Instalação local** in Portuguese. Use only the options for the active mode:

| Update mode | 1 | 2 | 3 |
| --- | --- | --- | --- |
| Retail (`atualizar` or `atualizar retail`) | Instalar Retail (`_retail_`) | Abortar instalação | |
| PTR (`atualizar ptr`) | Instalar PTR (`_ptr_`) | Instalar XPTR (`_xptr_`) | Abortar instalação |
| Both (`atualizar ambos`) | Instalar Retail + PTR (`_retail_` + `_ptr_`) | Instalar Retail + XPTR (`_retail_` + `_xptr_`) | Abortar instalação |

Present the selected row as a numbered list. Accept exactly the populated numeric choices for that mode. For any other reply, ask again with the same choices before running anything. An install choice is sufficient authorization. Pass the mode explicitly with `-Only` and the number with `-InstallChoice` to the maintained installer. A valid supplied choice skips the standalone prompt. An abort choice ends the stage without invoking either script or modifying files. Retail sync as a prerequisite for PTR does not authorize a Retail install.

After an install choice, establish that the operational scripts and only the selected WoW AddOns folders are available. If unavailable, report the failure and stop. Reuse the Python preflight and read [install commands](references/install-commands.md). Run the installer directly in the current Codex session. After success, run the line-ending fixer in the same mode, passing the exact selected PTR path for PTR or Both. If UAC appears, ask the user to approve it manually and wait.

Handle the menu and authorized installation in the main chat. Do not request a subagent for routine execution.

All authorized installations must use the shared managed-folder transaction and per-destination fingerprint policy in [install commands](references/install-commands.md). Use the maintained `.tools/install/` sources, keeping legacy record storage unchanged. Use backups only for failure recovery. Automatically remove the current operation's folder and manifest backups after success or verified complete rollback; preserve them after incomplete recovery. Warn if cleanup fails. Never delete preexisting backups, perform prefix-based cleanup or bypass pending recovery markers.
