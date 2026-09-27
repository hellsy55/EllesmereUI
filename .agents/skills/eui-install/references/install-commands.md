# Install and line-ending commands

The operational scripts live in `C:\Users\jonat\Desktop\EUI`. Run commands directly in the current Codex session, which normally has administrator rights. Do not use `start`, `Start-Process`, or any separate window; the direct process naturally waits for completion, so no extra detection, file checking, or window-closing handling is needed.

Repository/Codex metadata such as `AGENTS.md`, `.agents/`, and `.codex/` must not be copied into the installed addon. The operational installer excludes `AGENTS.md` through robocopy's `/XF` filter and `.agents` and `.codex` through `/XD` when copying both the core and `EllesmereUI*` modules into staging, preserving the existing exclusions.

| Mode | Install | Line-ending fix after successful install |
| --- | --- | --- |
| Retail | `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\jonat\Desktop\EUI\atualizar-eui.ps1" -Only Retail` | `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\jonat\Desktop\EUI\corrigir-fim-de-linha.ps1" -Only Retail` |
| PTR | `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\jonat\Desktop\EUI\atualizar-eui.ps1" -Only PTR` | `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\jonat\Desktop\EUI\corrigir-fim-de-linha.ps1" -Only PTR` |
| Both | `"C:\Users\jonat\Desktop\EUI\Atualizar_ambos_EUI.bat"` | `"C:\Users\jonat\Desktop\EUI\Corrigir_Fim_de_Linha.bat"` |

The Both batch runs `atualizar-eui.ps1` without `-Only`, installing Retail from `12.1-new-features` and PTR from `12.1.5-PTR-features`, in that order, into their separate folders. The Both line-ending batch fixes both folders. Retail install folder: `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns`. PTR install folder: `C:\Program Files (x86)\World of Warcraft\_xptr_\Interface\AddOns`. PTR downloads the ZIP of `12.1.5-PTR-features` and installs only in the PTR folder. Run no line-ending command when installation did not run or did not complete successfully.
