# FILE MAPPING — live tree → 12.1 tree

Where a live diff's file lands on 12.1. Anything not listed maps to itself.
Apply hunks by ANCHOR (function name / distinctive code token), never line
numbers. Remember: the 12.1 comment sweep changed comments only — code lines
are byte-identical wherever 12.1 didn't rewrite the logic, so
`git apply --reject --ignore-whitespace` first, hand-apply the .rej hunks.

## Moved to the LoadOnDemand options addon (EllesmereUIOptions/)
| live path | 12.1 path |
|-----------|-----------|
| EUI__General_Options.lua | EllesmereUIOptions/EUI__General_Options.lua |
| EUI_PartyMode_Options.lua | EllesmereUIOptions/EUI_PartyMode_Options.lua |
| EllesmereUI_Widgets.lua | EllesmereUIOptions/EllesmereUI_Widgets.lua — EXCEPT the extracted regions below |
| EllesmereUI<Child>/EUI_<Child>_Options.lua (every child, incl. all 8 QoL options + EllesmereUIDataBars_Options.lua) | EllesmereUIOptions/<same basename> |
| EllesmereUIRaidFrames/EUI_RaidFrames_ManagerPages.lua | EllesmereUIOptions/EUI_RaidFrames_ManagerPages.lua |
| EllesmereUIUnitFrames/EUI_PlayerAuraBars_ManagerPages.lua | EllesmereUIOptions/EUI_PlayerAuraBars_ManagerPages.lua |

12.1-side extras in those files (do not remove when porting): each child options
file opens with an `EllesmereUI._ModuleNS[...]` gate and ends its registration
initFrame with an `IsLoggedIn()` re-fire line.

## Widgets regions extracted to EllesmereUI_UICore.lua (parent, resident)
A live hunk inside any of these Widgets regions lands in EllesmereUI_UICore.lua:
- MakeStyledButton + WB_COLOURS/RB_COLOURS
- DisabledTooltip
- widget tooltip system (tooltipFrame, GetTooltipFrame, IsPanelFamilyAnchor, ShowWidgetTooltip, HideWidgetTooltip)
- accent/theme/profile-accent block (DEFAULT_ACCENT, GetAccentColor, GetActiveTheme, ResolveThemeColor, UpdateAccentElements + fade ticker, ApplyAccentAnimated/Live, SetActiveTheme, SetAccentColor, ApplyAccentColorLive, GetActiveProfileData, SetActiveProfileAccent, GetActiveAccentState, ResolveProfileAccent, ResolveActiveAccent, RefreshAccent, GetPlayerClassColor, ResetAccentColor, ResetTheme)
- ShowContextMenu

## Bags split
| live region (EllesmereUIBags/EUI_Bags_Options.lua) | 12.1 path |
|---|---|
| BAGS_DEFAULTS + Lite.NewDB + `EllesmereUI._bagsDB` + PLAYER_LOGIN seeding/migration handler | EllesmereUIBags/EllesmereUIBags_DB.lua |
| everything else (page building, RegisterModule) | EllesmereUIOptions/EUI_Bags_Options.lua |

## Gone on 12.1 (port class N/A or G)
- Locales/_keys.txt -- NEVER port (user rule 2026-08-07): it is regenerated from source at 12.1 launch via .tools/extract-locale-keys.sh, so porting it is wasted work. Locale TRANSLATION files (deDE/koKR/...) still port normally.
- EllesmereUIBasics/* — retired on 12.1 (folder + its 7 migrations). Live changes here: N/A, log the reason.
- EllesmereUIFriends/EUI_Friends_Groups_121.lua — deleted on 12.1 (SocialUI rewrite). Live changes: class G against the 12.1 Friends architecture.
- `else`-branches of `IS_121` gates (frozen 12.0 code) — N/A. **The `if IS_121` TRUE-branches ARE 12.1 code: port those, into the ungated 12.1 call site.**
- UpgradeCalc char-sheet hook: on 12.1 it lives in EllesmereUIQoL/EUI_UpgradeCalc.lua (uses `Opts()`), not the options file.

## Behavioral era differences (context when porting, not paths)
- Login loader: live `EnsureLoaded()` at login (UnlockMode/CDM) ↔ 12.1 `EnsureUnlockCore()`. A live change in that machinery maps to the split design (EllesmereUI.lua: EnsureUnlockCore + EnsureOptionsLoaded + EnsureLoaded).
- RegisterModule ALLOWED table on 12.1 contains `EllesmereUIOptions`, not `EllesmereUIBasics`.
- Migrations: live has 98 RegisterMigration calls, 12.1 has 91 (the 7 basics-family ones are gone). New live migrations port normally (append; watch ordering only if they read basics keys — then N/A).
- Aura rendering: 12.1 is AuraKit + container system (NP/RF/UF _AuraContainers files). Live aura changes in legacy pools/renderers = class G — reimplement per the container architecture (see project_midnight_aura_rework_baseline memory, contracts 1-7).
- Reset-All svNames list on 12.1 lacks EllesmereUIBasicsDB; Profiles import has no Basics wiring.
