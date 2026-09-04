# EllesmereUI

## Unreleased - PTR 12.1.5 test build

Local build for testing the 12.1.5 PTR aura-engine changes before they hit
live. Every new call is guarded by an existence check on the button/container
API it depends on (`button.AddPandemicActiveAnimation`, `button.SetCasterName`,
`container.SetEditModePreviewEnabled`, etc.), so this build still runs
unchanged on live 12.1 and on PTR builds that predate a given API -- the new
behavior only lights up once the client actually has it.

**Testable now, via Options:**
- **Pandemic Pulse (PTR)** / **Show Caster Name (PTR)** -- AuraKit engine
  support (`style.pandemicGlow`, `style.showCasterName`) wired into Options:
  - Unit Frames: Buff Settings cog and Debuff Settings cog (buffs, debuffs,
    and Boss Frames -- Boss reuses the exact same `BuildStyle`/`SettingsFor`
    pipeline as Player/Target/Focus, so the only gap was its own smaller,
    duplicated cog popup not carrying the two rows yet).
  - Raid Frames: new row under Debuffs (Tooltips / Show Duration Swipe).
  - Nameplates: new row under Auras -> Duration/Stacks (debuffs only).
- **Aura Caster In Tooltip (PTR)** -- QoL page: thin wrapper over the native
  `tooltipShowAuraCasterNames` CVar.
- **Preview Auras In Edit Mode (PTR)** -- QoL page: wraps the new
  `CustomAuraContainer:SetEditModePreviewEnabled`. Global switch (not
  per-frame); re-drives every live container immediately, defaults on
  (unchanged stock behavior) so it does nothing until explicitly turned off.
- **Warrior Charges `minApplications`** -- Whirlwind Stacks / Sweeping
  Strikes charge bars register with `minApplications = 1` (no Options row;
  see below for why).

**Implemented but not exposed anywhere yet:**
- `AK.SetGroupEnabled` / `AK.SetSlotEnabled` / `AK.SetItemEnchantmentEnabled`
  -- generic, API-gated wrappers over the three new disable APIs. No consumer
  wired in: every module in this suite currently manages aura visibility
  through full candidateFilters/maxFrameCount rebuilds, not a disable flag,
  and retrofitting the Buff/Debuff Manager files (hundreds of KB each) onto
  this is its own project rather than a drive-by addition.

**Fixed along the way (not new PTR features, found while wiring the above):**
- `StyleTableFP` (Unit Frames) and `StyleFPFor` (Nameplates) never included
  `dispelBorder` in their change fingerprint, so toggling "Dispel Type
  Borders" alone did nothing until some unrelated field also changed and
  dragged a restyle along with it. Both new PTR fields (`pandemicGlow`,
  `showCasterName`) would have had the identical bug; all three are folded
  into the fingerprints now. Raid Frames' `DebuffStyleFP` was already
  correctly structured, just missing the two new keys, which are added.
- Audited every `AddDispelTypeTexture` / `AddPandemicRegion` call site: none
  of ours ever captured the old return-value index or called the paired
  `Remove*` API, so the "no longer returns an index / Remove takes a region
  reference" change needed no code changes here.

**Deliberately not exposed as a toggle:**
- `minApplications` on the Warrior Charges bars isn't a visual preference --
  it's "don't show a bar with a stale/zero count" -- so it's just on by
  default in code, with a silent degrade (retries without the option) on any
  build that doesn't recognize the key yet.

**Not testable in this addon at all** (client-internal fixes / namespaces
with no natural addon hook): the `tooltipShowAuraSpellIDs` line color/locale
fix, the Mythic+ enemy-forces tooltip line type, macro `#showtooltip` ping
resolution, the long-duration aura render fix, the `EnumerateFrames`
performance fix, the `Hide` vs `HideUIPanel` Game Menu fix, castbar ID
per-unit-token uniqueness, `TimedSignalMap`/`CreateTimedSignalCallbackMap`,
`CreateFrameWithOptions`, `roundLayoutToNearestPixel`, `C_Intl`. `C_Weather`
could become a real feature (a weather line somewhere) but needs a decision
on which module should host it before it's worth building.

## [v8.8.2](https://github.com/EllesmereGaming/EllesmereUI/tree/v8.8.2) (2026-08-11)
[Full Changelog](https://github.com/EllesmereGaming/EllesmereUI/compare/v8.8.1...v8.8.2) [Previous Releases](https://github.com/EllesmereGaming/EllesmereUI/releases)

- Release v8.8.2  
