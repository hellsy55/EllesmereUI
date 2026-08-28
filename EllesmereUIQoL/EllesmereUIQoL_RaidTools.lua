if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_RaidTools.lua -- Raid control panels (QoL: Raid Tools page)
--
--  TWO content groups -- Group & Pull (ready/role/convert/disband + the pull
--  timer; plain buttons) and Markers (target row + world row; secure buttons,
--  placeable mid-combat) -- shown either as one combined window (default) or
--  as two independently positioned windows.
--
--  Which Group & Pull buttons exist is a SETTING, not a build fact: Role
--  Check, Convert and Disband each have a switch, and a pull slot set to 0
--  seconds drops out. Buttons are still created once, at build; the layout
--  pass (LayoutGroupContent) re-flows the survivors across the rows and is the
--  only writer of the content height the shells are sized from.
--
--  SHOW MODE (p.mode) replaces the old shared-visibility system outright:
--
--    "never"  -- the default. NOTHING exists: no frames, no events, no
--                bindings, no unlock rows. True zero cost.
--    "raid"   -- auto-shows in a raid group ([group:raid] state driver).
--    "group"  -- auto-shows in any group ([group] state driver).
--    "always" -- always shown (no driver; the visible attribute just stays
--                true).
--
--  The panel shows in every group the mode's driver puts it in, whether or
--  not you have leader or assist -- there is no whole-feature gate on that
--  anymore. RefreshPermissions still dims/disables the individual controls
--  the server would refuse (ready check, role check, convert, disband, the
--  markers), so the panel is always visible but only as capable as your
--  rank. AssistSuppressed and RefreshAssistGate remain as the plumbing for
--  that per-button gate, now permanently reporting "not suppressed".
--
--  The Toggle Raid Tools keybind works in every active mode, and what it
--  toggles follows Default to Collapsed When Shown: with it ON the key rocks
--  between the collapsed icon and the full windows (the icon is the minimized
--  state, so hiding would be redundant); with it OFF the key is a plain
--  show/hide of the full windows, riding the override on top of the mode's
--  verdict. In the driver modes a TRANSITION reclaims control; in always
--  mode the override holds until the next settings pass.
--
--  COMBAT MODEL -- read this before changing anything here.
--
--  Marker buttons are SecureActionButtonTemplate, built once on first
--  non-never Apply and never re-anchored, re-parented or resized in combat.
--  The window shells are SecureHandlerState frames, which makes THEM
--  protected; that dictates who may change visibility, and when:
--
--    * The STATE DRIVER, the KEYBIND, the collapsed icon's expand click and
--      the collapse buttons all work in combat -- every one is a hardware
--      click or driver transition running the secure "apply" snippet.
--    * LUA does not. Show/Hide AND SetAttribute on a protected frame are
--      blocked in lockdown, so every options-driven change (mode, layout,
--      scale, position) defers behind applyPending and completes on
--      PLAYER_REGEN_ENABLED.
--
--  VISIBILITY STATE -- attributes on each shell and on the collapsed icon,
--  one writer each:
--
--    enabled       -- may this frame ever show. Written by Apply, OOC only.
--    visible       -- the driver's current verdict; false when no driver.
--                     Written by _onstate (and Apply's OOC settle).
--    override      -- "" / "show" / "hide" from the keybind; cleared by
--                     driver transitions and settings passes.
--    expanded      -- windows (true) vs collapsed icon (false). Flipped by
--                     the icon's expand click and the collapse buttons;
--                     re-seeded from startexpanded on driver transitions and
--                     on every keybind "show".
--    startexpanded -- the seed for EVERY show (driver, settings pass,
--                     keybind): NOT Default to Collapsed When Shown. Turning
--                     that toggle off is how the keybind becomes a plain
--                     full-window toggle.
--
--  "apply" folds these into Show/Hide: shells show when visible-and-expanded,
--  the icon shows when visible-and-collapsed. It is the ONLY place any of
--  these frames is shown or hidden.
--
--  SHOW AS (p.showAs) owns the window composition outright -- there are no
--  separate per-panel enable toggles:
--
--    "one"     -- the default. Both content groups in the Group & Pull shell,
--                 which grows to fit and retitles to "Raid Tools"; ONE unlock
--                 element positioned by pos.Group. The markers holder
--                 re-parents (OOC) into the shell; holders are plain frames,
--                 so the move is an ordinary SetParent and the secure buttons
--                 never change parents themselves.
--    "two"     -- each content group in its own shell, two unlock elements.
--                 The Markers shell drops its collapse button here: one
--                 collapse control (Group & Pull's) folds the whole feature.
--    "group"   -- only the Group & Pull shell exists on screen.
--    "markers" -- only the Markers shell exists on screen; the collapsed
--                 icon anchors to IT in this mode.
--
--  One Window Scale (p.scale) covers every form: both shells and the
--  collapsed icon wear the same value, whichever windows the Show as choice
--  puts on screen.
-------------------------------------------------------------------------------
local _, ns = ...

local InCombatLockdown = InCombatLockdown
local IsEncounterInProgress = IsEncounterInProgress
local UnitIsGroupLeader, UnitIsGroupAssistant = UnitIsGroupLeader, UnitIsGroupAssistant
local IsInRaid, IsInGroup = IsInRaid, IsInGroup
local GetNumGroupMembers, GetRaidRosterInfo = GetNumGroupMembers, GetRaidRosterInfo
local PromoteToAssistant, DemoteAssistant = PromoteToAssistant, DemoteAssistant
local SetRaidTargetIconTexture = SetRaidTargetIconTexture

-- Layout constants. Content geometry is decided once at build; only scale,
-- and which holders a shell carries, are user-facing.
local PANEL_W      = 236
local PAD          = 10
local TOPBAR_H     = 25    -- the Window Skins title band
local ROW_H        = 22
local ROW_GAP      = 4
local CONTENT_TOP  = TOPBAR_H - 2
-- Marker buttons span the full panel width regardless of this size: the row
-- step is derived from it ((PANEL_W - PAD*2 - MARKER_SZ) / 8), so a smaller
-- icon just breathes more between neighbours.
local MARKER_SZ    = 23
local MARKER_LBL_H = 10
local ICON_SZ      = 30
local PULL_SLOTS   = 3
local PULL_DEFAULTS = { 3, 5, 10 }   -- also seeded into DB_DEFAULTS below
ns.PULL_DEFAULTS = PULL_DEFAULTS

-- The collapse ("close") button sits at the same literal corner Open
-- Direction anchors the collapsed icon to, so the panel closes at the exact
-- spot it opened from. ApplyLayout leaves it room instead of confining it to
-- the title band: the title's inset widens (TOPLEFT only -- every other
-- corner already lands clear of the title text) and a BOTTOM corner's shell
-- gets a little extra height underneath (the content column always fills
-- top-down regardless of opening direction, so that padding is otherwise
-- unused space at the bottom edge, not a layout flip).
local BTN_MARGIN         = 6
local BTN_TITLE_RESERVE  = PAD + BTN_MARGIN + 14 + 6  -- inset, gap, button, clearance
local BTN_BOTTOM_RESERVE = BTN_MARGIN + 14 + 5         -- gap, button, clearance
local COLLAPSE_OFFSET = {
    TOPLEFT     = {  BTN_MARGIN, -TOPBAR_H / 2 },
    TOPRIGHT    = { -BTN_MARGIN, -TOPBAR_H / 2 },
    BOTTOMLEFT  = {  BTN_MARGIN,  BTN_MARGIN },
    BOTTOMRIGHT = { -BTN_MARGIN,  BTN_MARGIN },
}

-- Raid Groups cog: opens the group-composition window (EllesmereUIQoL_
-- RaidGroups.lua). Lives only on the Group & Pull shell, riding the inward
-- side of the close button -- same corner, one gap further into the panel --
-- so it never competes with Open Direction for its own spot.
local COG_SZ  = 14   -- matches the shell's own close button
local COG_GAP = 4
-- Raid Check button rides the cog's own inward side the same way, so the row
-- reads close -> Raid Groups -> Raid Check without any of them competing
-- with Open Direction for a spot. The title reserve below has to know about
-- both riders, not just the first.
local RAIDCHECK_GAP = COG_GAP
local GROUP_COG_RESERVE = (COG_GAP + COG_SZ) + (RAIDCHECK_GAP + COG_SZ) + 6  -- two riders, gap, clearance

-- Consumable/repair report row: five more riders past Raid Check, same
-- corner, chained further inward. Full name on each (not an abbreviation);
-- width is measured per-label at layout time (see ApplyLayout) rather than
-- fixed, since "Repair"/"Vantus" and "Food"/"Rune" are not the same length.
-- REPORT_BTN_PAD is the horizontal padding inside each button, both sides.
local REPORT_GAP = COG_GAP
local REPORT_BTN_PAD = 5
local REPORT_COLUMNS = {
    { key = "flask",      title = "Flask" },
    { key = "food",       title = "Food" },
    -- Abbreviated on the button itself (still "Repair" in the tooltip) --
    -- the longest full name here, and the one most worth trimming.
    { key = "durability", title = "Repair", label = "Rep" },
    { key = "rune",       title = "Rune" },
    { key = "vantus",     title = "Vantus" },
}

-- Make Everyone Assistant checkbox: first row of Group & Pull content.
local ASSIST_CHK_SZ = 14

-- Raid Groups row: one toggle per raid subgroup, showing/hiding it on the
-- EllesmereUI Raid Frames the way that addon's own group filter does.
local RAID_GROUPS = 8
local RAIDGROUPS_ROW_LABEL = "Raid Groups"
local RAIDGROUPS_ROW_NO_RF = "Requires EllesmereUI Raid Frames"

-------------------------------------------------------------------------------
--  Window Skins look, replicated
--
--  These panels wear a close cousin of the Blizz UI Enhanced window skins:
--  a flat black backdrop (originally the modern_blizz art cover-fit behind a
--  black wash, replaced with plain black -- see SkinPanelBg), a 25px black
--  title band, the AdventureMap_TopBorder frame atlas (1px gray fallback),
--  and flat 0.08-gray buttons with a 1px 0.2-gray border and a white 0.1
--  hover. The values are copied from the WSkin engine's Shell/Button recipe
--  ON PURPOSE rather than calling it: WSkin lives in EllesmereUIBlizzardSkin,
--  a sibling child addon the user may not have enabled, and QoL must not
--  depend on it.
-------------------------------------------------------------------------------
local BORDER_ATLAS = "AdventureMap_TopBorder"
-- Theme grays (WSkin.Theme): button fill / border line.
local BTN_R, BTN_G, BTN_B, BTN_A = 0.08, 0.08, 0.08, 0.92
local BRD_R, BRD_G, BRD_B, BRD_A = 0.2, 0.2, 0.2, 1

-- Shell backdrop: flat black fill + a slightly darker title band. Was the
-- WSkin art texture (modern_blizz.png) cover-fit behind a black wash; that
-- image reads as a visibly different shade panel to panel (and top to
-- bottom within one panel, since cover-fit crops it differently at every
-- height), so it is a plain color here instead -- one black, everywhere,
-- regardless of how tall a given shell ends up.
local function SkinPanelBg(f)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetColorTexture(0, 0, 0, 1)
    bg:SetAllPoints(f)
    local topBar = f:CreateTexture(nil, "BACKGROUND", nil, -5)
    topBar:SetColorTexture(0, 0, 0, 0.5)
    topBar:SetPoint("TOPLEFT")
    topBar:SetPoint("TOPRIGHT")
    topBar:SetHeight(TOPBAR_H)
    -- No art left to re-crop on a height change; kept as a harmless no-op so
    -- ApplyLayout's post-resize f._bgFit() calls have nothing to break.
    f._bgFit = function() end
end

-- Window frame: the atlas border the skins use, 1px gray line if the atlas
-- ever disappears from the client.
local function SkinPanelBorder(f)
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(BORDER_ATLAS)
    if not info then
        EllesmereUI.MakeBorder(f, BRD_R, BRD_G, BRD_B, BRD_A, EllesmereUI.PP)
        return
    end
    local ov = CreateFrame("Frame", nil, f)
    ov:SetAllPoints(f)
    ov:SetFrameLevel(f:GetFrameLevel() + 6)
    local tex = ov:CreateTexture(nil, "OVERLAY", nil, 7)
    tex:SetAtlas(BORDER_ATLAS)
    tex:SetAllPoints(ov)
end

-- Button chrome: flat fill, 1px line, white hover on the HIGHLIGHT layer
-- (Buttons show that layer on mouseover natively, so no scripts).
local function SkinButtonChrome(b)
    local fill = b:CreateTexture(nil, "BACKGROUND")
    fill:SetColorTexture(BTN_R, BTN_G, BTN_B, BTN_A)
    fill:SetAllPoints(b)
    -- Stored on the button: the raid group toggles recolor it white/gray to
    -- show whether that group is currently drawn (PaintRaidGroup).
    b._border = EllesmereUI.MakeBorder(b, BRD_R, BRD_G, BRD_B, BRD_A, EllesmereUI.PP)
    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetColorTexture(1, 1, 1, 0.1)
    hover:SetAllPoints(b)
end

-- The collapsed-state button IS this image: no chrome, no border, no inset.
local COLLAPSED_ICON_TEX = "Interface\\AddOns\\EllesmereUI\\media\\icons\\raid-tools.png"

-- Canonical section list. Build order, stack order, DB key set, window titles
-- and unlock-mover labels all derive from this one table.
--
-- `label` reaches EllesmereUI.L as a variable, which the static key extractor
-- cannot see -- the documented arrangement for exactly this case (see the
-- header of .tools/extract-locale-keys.sh); the in-game /euiloc harvester picks
-- them up, the same way every widget label in the suite is already handled.
local SECTIONS = {
    { key = "Group",   label = "Group & Pull" },
    { key = "Markers", label = "Markers" },
}

-- One-window title; reaches L as a variable like the section labels.
local COMBINED_LABEL = "Raid Tools"

-- Prefix for this feature's unlock-mode element keys. Used both to register
-- them and to ask the anchor system about them, so the two cannot drift.
-- These keys persist in saved anchors -- renaming breaks existing links.
local UNLOCK_KEY = "EUI_RaidTools_"

local SECTION_KEYS = {}
local SECTION_LABEL = {}
for _, def in ipairs(SECTIONS) do
    SECTION_KEYS[#SECTION_KEYS + 1] = def.key
    SECTION_LABEL[def.key] = def.label
end

local db
local applyPending             -- true when combat blocked an Apply()
local groupsPending             -- true when combat blocked a raid-frame re-render
local wasInGroup = false       -- edge-detects joining a group, for ResetGroupFilter
local previewOn = false        -- Raid Tools settings page is in front (see ApplyVisibility)
local lastSuppressed           -- assist gate verdict currently ON SCREEN (see AssistSuppressed)
local toggleButton             -- keybind target; also the out-of-combat path
local sections = {}            -- key -> shell frame
local shellTitle = {}          -- key -> title fontstring
local groupHolder, markersHolder   -- plain content holders (see header)
local iconBtn                  -- collapsed-state square
local raidGroupsCogBtn          -- opens the Raid Groups composition window (Group shell only)
local raidCheckBtn              -- re-runs and shows the Raid Check window on demand (Group shell only)
local reportBtns = {}           -- Flask/Food/Repair/Rune/Vantus report buttons (Group shell only)
local assistCheckRow, assistCheckTex   -- Make Everyone Assistant row (Group shell, raid-only)
-- Markers are fixed at build; the Group & Pull height follows the settings and
-- is re-computed by LayoutGroupContent on every Apply.
local GROUP_CONTENT_H, MARKERS_CONTENT_H
local Apply                    -- forward: the event handler closes over it
local ApplyMouseoverFade       -- forward: ApplyVisibility and the mouseover ticker close over it

-- ONE representation of each secure decision, run from both paths.
--
-- The keybind clicks the button, which is the only thing that works during
-- combat. Out of combat the same snippet is run through SecureHandlerExecute
-- instead of being re-implemented in Lua. EllesmereUIRaidFrames.lua does
-- exactly this, for exactly this reason: the driver manager only fires the
-- attribute handlers on value CHANGES, so a reapply with unchanged states
-- would otherwise never run.
local RUN_APPLY = [[ self:RunAttribute("apply") ]]

-- The keybind's job depends on Default to Collapsed When Shown:
--
--   ON  -- the icon IS the minimized state, so hiding would be redundant.
--          The key rocks between the icon and the full windows (collapse /
--          expand); from fully hidden it shows the windows directly, since
--          the press means the tools are wanted NOW.
--   OFF -- a plain show/hide of the full windows.
--
-- The branch is read off the icon's startexpanded (false = collapse mode),
-- so the snippet needs no config attribute of its own.
local TOGGLE_SNIPPET = [[
    local n = self:GetAttribute("count") or 0
    local icon = self:GetFrameRef("icon")
    local anyWin, iconShown = false, false
    for i = 1, n do
        local f = self:GetFrameRef("s" .. i)
        if f and f:IsShown() then anyWin = true end
    end
    if icon and icon:IsShown() then iconShown = true end

    local collapseMode = icon and not icon:GetAttribute("startexpanded")
    if collapseMode then
        if anyWin then
            -- Windows up: collapse to the icon. Visibility is untouched, so
            -- whatever put the windows up (driver or override) keeps the icon
            -- up in their place.
            for i = 1, n do
                local f = self:GetFrameRef("s" .. i)
                if f then
                    f:SetAttribute("expanded", false)
                    f:RunAttribute("apply")
                end
            end
            icon:SetAttribute("expanded", false)
            icon:RunAttribute("apply")
        else
            -- Icon up, or nothing up: expand to the windows. The override
            -- also covers the fully-hidden case (driver currently saying no).
            for i = 1, n do
                local f = self:GetFrameRef("s" .. i)
                if f then
                    f:SetAttribute("override", "show")
                    f:SetAttribute("expanded", true)
                    f:RunAttribute("apply")
                end
            end
            icon:SetAttribute("override", "show")
            icon:SetAttribute("expanded", true)
            icon:RunAttribute("apply")
        end
        return
    end

    local ov
    if anyWin or iconShown then ov = "hide" else ov = "show" end
    for i = 1, n do
        local f = self:GetFrameRef("s" .. i)
        if f then
            f:SetAttribute("override", ov)
            if ov == "show" then
                f:SetAttribute("expanded", f:GetAttribute("startexpanded"))
            end
            f:RunAttribute("apply")
        end
    end
    if icon then
        icon:SetAttribute("override", ov)
        if ov == "show" then
            icon:SetAttribute("expanded", icon:GetAttribute("startexpanded"))
        end
        icon:RunAttribute("apply")
    end
]]

-- Expand (the icon's own click) and collapse (the shells' corner buttons):
-- flip `expanded` everywhere and re-apply. Both run in combat as hardware
-- clicks on secure buttons.
local EXPAND_SNIPPET = [[
    local n = self:GetAttribute("count") or 0
    for i = 1, n do
        local f = self:GetFrameRef("s" .. i)
        if f then
            f:SetAttribute("expanded", true)
            f:RunAttribute("apply")
        end
    end
    self:SetAttribute("expanded", true)
    self:RunAttribute("apply")
]]
local COLLAPSE_SNIPPET = [[
    local n = self:GetAttribute("count") or 0
    for i = 1, n do
        local f = self:GetFrameRef("s" .. i)
        if f then
            f:SetAttribute("expanded", false)
            f:RunAttribute("apply")
        end
    end
    local icon = self:GetFrameRef("icon")
    if icon then
        icon:SetAttribute("expanded", false)
        icon:RunAttribute("apply")
    end
]]

-- Every fontstring is registered on the OUR-frame that owns it (`_fonts`),
-- and ApplyFonts walks the small fixed owner list -- no module-level registry
-- to keep in sync with frame lifetime. MakeFont (like every options-panel
-- helper) hardcodes the options-panel font; on-screen text has to resolve
-- through GetFontPath instead, or these panels would be the only ones in the
-- suite ignoring the Global Font setting.
local FONT_KEY = "extras"      -- QoL's key in EllesmereUI._addonKeyToFolder
local fontOwners = {}          -- filled at build: shells + holders
local function TrackFont(owner, fs, size)
    local t = owner._fonts
    if not t then t = {}; owner._fonts = t end
    t[#t + 1] = { fs = fs, size = size }
    return fs
end
local function ApplyFonts()
    local path = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath(FONT_KEY)
    if not path then return end
    for _, owner in ipairs(fontOwners) do
        local t = owner._fonts
        if t then
            for _, e in ipairs(t) do
                local _, _, flags = e.fs:GetFont()
                e.fs:SetFont(path, e.size, flags or "")
            end
        end
    end
end

local groupButtons = {}        -- plain buttons, enable-gated on assist
local markerButtons = {}       -- secure buttons, dimmed on assist
local pullButtons = {}         -- fixed set of 3; only the ones above 0s show
local raidGroupButtons = {}    -- plain buttons, gated on the raid frames only
local raidGroupsRowLabel
-- Individually hideable content. Every one of these is created at build and
-- kept for the lifetime of the session; the layout pass decides which of them
-- reach the screen. Ready Check is the one action button with no switch -- a
-- raid panel without it has no reason to exist.
local readyButton, roleButton, convertButton, disbandButton, stopButton

-- Both marker rows draw Blizzard's own raid target sheet -- the texture the
-- rest of the suite already uses for markers, in nameplates and raid frames.
local MARKER_SHEET = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

-- The sheet's SYMBOL order (1 Star, 2 Circle, 3 Diamond, 4 Triangle, 5 Moon,
-- 6 Square, 7 Cross, 8 Skull) is NOT the WORLD marker ID order (1 Blue,
-- 2 Green, 3 Purple, 4 Red, 5 Yellow, 6 Orange, 7 Silver, 8 White). Each
-- flare carries its symbol, so the button shows the symbol and this maps it
-- to the flare that actually wears it -- without it, clicking Star (symbol 1)
-- dropped the BLUE flare (world ID 1).
local SYMBOL_TO_WORLD = { 5, 6, 3, 2, 7, 1, 4, 8 }

-- One slice of the shared EllesmereUIQoLDB profile, the same arrangement
-- BattleRes and Bloodlust use: each QoL feature merges its own defaults into
-- the SAME profile table under its own key.
local DB_DEFAULTS = {
  profile = {
    raidTools = {
        -- "never" | "raid" | "group" | "always" (see header). Never = the
        -- feature does not exist at runtime.
        mode          = "never",
        -- Toggle Raid Tools key ("SHIFT-R" form). Profile-stored and applied
        -- as an override binding, exactly like Action Bars' toggleVisKey.
        toggleKey     = false,
        -- Default to Collapsed When Shown: EVERY show (driver, settings pass,
        -- keybind) starts as the small icon; click it to expand. Turning this
        -- off makes the keybind a plain full-window toggle.
        collapsedIcon = true,
        -- "one" | "two" | "group" | "markers" (see header). The single owner
        -- of window composition; there are no per-panel enable toggles.
        showAs        = "one",
        -- One scale for the whole feature: whichever windows the Show as
        -- choice puts on screen (and the collapsed icon) all wear it.
        scale         = 1,
        -- "always" | "mouseover". Always keeps the shown shells and the
        -- collapsed icon at full opacity; mouseover fades each of them out
        -- (alpha 0, still shown/clickable for the secure state machine)
        -- until the cursor sits over it. Detected by a polling IsMouseOver
        -- check rather than OnEnter/OnLeave, since a child button (marker,
        -- collapse, etc.) stealing mouse focus would otherwise fire the
        -- shell's OnLeave while hovering something inside it. Purely a
        -- display fade layered on top of the mode/showAs verdict -- it never
        -- touches Show/Hide, so it is unaffected by combat lockdown.
        visibility    = "always",
        -- FrameStrata for every shell and the collapsed icon: one of
        -- BACKGROUND/LOW/MEDIUM/HIGH/DIALOG. Same "one value, everything the
        -- feature draws" convention as scale and visibility.
        strata        = "MEDIUM",
        -- "downright" (default) | "downleft" | "upright" | "upleft". Which
        -- corner of a shell rides the collapsed icon's position -- that
        -- shared corner stays fixed on expand/collapse, so it is also the
        -- direction the panel visually opens (and where the close button
        -- lands). See AnchorCorner/DefaultPos. Named growDir to match the
        -- upstream "Menu Grow Direction" option (formerly a separate
        -- openDirection setting on this branch; merged into one).
        growDir = "downright",
        -- Auto-Minimize: once the full windows have sat expanded, cursor
        -- off them, for autoMinimizeDelay seconds straight, they collapse
        -- back to the icon on their own -- the exact effect the corner
        -- collapse button already produces, just fired by a timer instead
        -- of a click. Hovering the panel pauses the count; it restarts from
        -- zero once the cursor leaves. Off by default; the delay only
        -- matters while it's on.
        autoMinimize      = false,
        autoMinimizeDelay = 30,
        -- Three slots is a LAYOUT choice (they fill one row beside Stop), not
        -- a security constraint -- the pull buttons are plain, only the marker
        -- buttons are secure. Growing the count later means growing the panel,
        -- nothing more.
        --
        -- 0 means "no button": the slot drops out of the row and the survivors
        -- share the width. All three at 0 takes the row away entirely, Stop
        -- included (see LayoutGroupContent).
        pullTimes     = { PULL_DEFAULTS[1], PULL_DEFAULTS[2], PULL_DEFAULTS[3] },
        -- Per-button switches for the three optional actions. Ready Check has
        -- none on purpose. Same flow rule as the pull slots: a hidden button
        -- leaves no hole, the rest close up.
        showRoleCheck = true,
        showConvert   = true,
        showDisband   = true,
        -- Per-section: pos[key] = { point, relPoint, x, y }
        pos           = {},
    },
  },
}

-- Our slice of the shared QoL profile, re-derived on every read -- the same
-- accessor BattleRes and MovementAlert use. Deliberately NOT cached: a profile
-- switch replaces the whole profile table, and a cached pointer would leave
-- the event handler, the slash command and the unlock callbacks writing into
-- an orphaned table.
--
-- A PURE READ, with no `or {}` seeding. Spec Overrides captures a page by
-- swapping the profile tables for read-tracking proxies: reading a table value
-- hands back a NEW proxy, and writing goes through to the real table. So
-- `t.x = t.x or {}` stores a proxy inside the real table, the next call wraps
-- that proxy in another, and reading through the stack overflows the C stack.
-- DB_DEFAULTS already guarantees the slice exists; the seeding was never
-- needed and is actively harmful here.
local function P()
    return db and db.profile and db.profile.raidTools
end

local function Mode()
    local p = P()
    return (p and p.mode) or "never"
end

-- The Show as choice, normalized: any unset/unknown value reads as "one".
local function ShowAs()
    local p = P()
    local v = p and p.showAs
    if v ~= "two" and v ~= "group" and v ~= "markers" then v = "one" end
    return v
end
ns.ShowAs = ShowAs

local function WindowScale()
    local p = P()
    return (p and p.scale) or 1
end

-- The Visibility choice, normalized: any unset/unknown value reads as
-- "always". Purely a fade layer -- see ApplyMouseoverFade.
local function Visibility()
    local p = P()
    local v = p and p.visibility
    if v ~= "mouseover" then v = "always" end
    return v
end
ns.Visibility = Visibility

local VALID_STRATA = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true }
-- The Strata choice, normalized: any unset/unknown value reads as "MEDIUM"
-- (the shells' and icon's original hardcoded strata, so existing profiles
-- are unaffected).
local function Strata()
    local p = P()
    local v = p and p.strata
    if not VALID_STRATA[v] then v = "MEDIUM" end
    return v
end
ns.Strata = Strata

-- Auto-Minimize: whether the windows should collapse themselves back to the
-- icon after sitting expanded for AutoMinimizeDelay() seconds. Off (false)
-- by default -- existing profiles get no new behaviour until the user opts
-- in on the options page.
local function AutoMinimize()
    local p = P()
    return p and p.autoMinimize and true or false
end
ns.AutoMinimize = AutoMinimize

-- The delay itself, in seconds. Any non-number (unset, or a stale/odd value
-- from a proxy) reads as the 30s default rather than fighting the ticker.
local function AutoMinimizeDelay()
    local p = P()
    local v = p and p.autoMinimizeDelay
    if type(v) ~= "number" or v < 1 then return 30 end
    return v
end
ns.AutoMinimizeDelay = AutoMinimizeDelay

-- Growth direction -> the shell corner that rides the collapsed icon (see
-- DB_DEFAULTS.openDirection). Anchoring icon and shell at the SAME corner of
-- both frames keeps that corner's screen position fixed across collapse and
-- expand, and puts the close (collapse) button at the same spot the icon
-- opened from:
--   TOPLEFT     -> extends right and down  (downRight, the original default)
--   TOPRIGHT    -> extends left and down   (downLeft)
--   BOTTOMLEFT  -> extends right and up    (upRight)
--   BOTTOMRIGHT -> extends left and up     (upLeft)
local GROW_DIRECTION_CORNER = {
    downright = "TOPLEFT",
    downleft  = "TOPRIGHT",
    upright   = "BOTTOMLEFT",
    upleft    = "BOTTOMRIGHT",
}

local function GrowDirection()
    local p = P()
    local v = p and p.growDir
    if not GROW_DIRECTION_CORNER[v] then v = "downright" end
    return v
end
ns.GrowDirection = GrowDirection

local function AnchorCorner()
    return GROW_DIRECTION_CORNER[GrowDirection()]
end

-------------------------------------------------------------------------------
--  Suite-styled widgets
--
--  Window-skin chrome (SkinPanelBg/Border, SkinButtonChrome) plus the suite
--  font pipeline (GetFontPath via TrackFont), so the panels read as skinned
--  Blizzard windows rather than stock Blizzard UI or the options panel.
-------------------------------------------------------------------------------

-- Enable state without touching the button's own scripts: dimming the whole
-- frame and cutting mouse input is both
-- simpler and immune to a hover re-lighting a disabled control.
local function SetButtonEnabled(b, on)
    b:SetAlpha(on and 1 or 0.35)
    b:EnableMouse(on)
end

-- Action button in the Window Skins style: flat fill, 1px line, white hover,
-- white label (WSkin.Button + WhiteButtonLabel, replicated). `needsLeader`
-- narrows the gate from assist to leader.
-- `needsLeader` narrows the gate from assist to leader. `registry` is the
-- list RefreshPermissions walks; the raid group toggles pass their own,
-- because they change what THIS client draws and so are never
-- permission-gated -- but they want the identical chrome, and a second
-- constructor would drift from this one the first time the skin moves.
local function MakeGroupButton(parent, text, width, onClick, needsLeader, registry)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, ROW_H)
    SkinButtonChrome(b)
    local lbl = TrackFont(parent, EllesmereUI.MakeFont(b, 11, nil, 1, 1, 1), 11)
    lbl:SetPoint("CENTER")
    if text ~= "" then lbl:SetText(EllesmereUI.L(text)) end
    b:SetScript("OnClick", onClick)
    b._lbl = lbl
    b.needsLeader = needsLeader
    registry = registry or groupButtons
    registry[#registry + 1] = b
    return b
end

-- Secure marker button. Action attributes are set here, at build, and never
-- touched again -- that is what makes them usable in combat.
--
-- The attribute names are SecureActionButtonTemplate's own contract, so two
-- details are dictated rather than chosen:
--   * slash commands are read from the SLASH_* globals. They are localized --
--     writing "/tm" or "/cwm" as a literal breaks every non-English client,
--     including this one.
--   * the worldmarker type takes `marker` as a STRING, and splits placing from
--     clearing across action1 and action2.
local function MakeMarkerButton(parent, index, kind)
    local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    b:SetSize(MARKER_SZ, MARKER_SZ)
    -- One phase only: the "!" prefix toggles the marker, so firing on both the
    -- down and the up would set it and immediately clear it again. useOnKeyDown
    -- is pinned because left unset it follows the ActionButtonUseKeyDown CVar,
    -- and at 0 the secure handler acts on the up phase we never register --
    -- every marker button goes dead.
    b:RegisterForClicks("AnyDown")
    b:SetAttribute("useOnKeyDown", true)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    b.icon = icon
    b._kind = kind

    if kind == "target" then
        -- Left: toggle this marker on the target. Right: clear it. With no
        -- target selected there is nothing for /tm to mark, so the second
        -- clause falls back to the "@player" macro unit tag -- this applies
        -- the mark to you directly without ever changing your actual
        -- selected target (unlike a "/tar player" fallback, which would).
        b:SetAttribute("type", "macro")
        if index == 0 then
            b:SetAttribute("macrotext",
                (SLASH_TARGET_MARKER1 or "/tm") .. " [exists] 0; [@player] 0")
        else
            b:SetAttribute("macrotext1",
                (SLASH_TARGET_MARKER1 or "/tm") .. " [exists] !" .. index .. "; [@player] !" .. index)
            b:SetAttribute("macrotext2",
                (SLASH_TARGET_MARKER1 or "/tm") .. " [exists] 0; [@player] 0")
        end
    elseif index == 0 then
        -- Clear-all is a macro, not a worldmarker action: the attribute form
        -- clears one index at a time.
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext",
            (SLASH_CLEAR_WORLD_MARKER1 or "/cwm") .. " " .. (ALL or "All"))
    else
        b:SetAttribute("type", "worldmarker")
        -- `index` is the SYMBOL the button shows; the attribute wants the
        -- world-marker ID of the flare carrying that symbol (see the map).
        b:SetAttribute("marker", tostring(SYMBOL_TO_WORLD[index]))
        b:SetAttribute("action1", "set")
        b:SetAttribute("action2", "clear")
    end

    if index == 0 then
        icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    else
        icon:SetTexture(MARKER_SHEET)
        SetRaidTargetIconTexture(icon, index)
    end

    -- No chrome on the marker grid: the symbols read best bare. Hover is an
    -- opacity lift on the icon itself (80% resting, 100% under the cursor),
    -- and the no-assist dim keeps priority -- a 0.4-dimmed button does not
    -- brighten on hover, so the dim never lies. _baseAlpha is ours to write
    -- (our CreateFrame'd button); RefreshPermissions owns its value.
    icon:SetAlpha(0.8)
    b._baseAlpha = 0.8
    b:SetScript("OnEnter", function(self)
        if (self._baseAlpha or 0.8) >= 0.8 then self.icon:SetAlpha(1) end
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(self._baseAlpha or 0.8)
    end)

    markerButtons[#markerButtons + 1] = b
    return b
end

-------------------------------------------------------------------------------
--  Permission gating
-------------------------------------------------------------------------------

-- Ready check, role check, countdown and markers all require lead or assist.
--
-- Solo counts as permitted. You are the only member, so nothing is being taken
-- from anyone, and the game already no-ops whatever does not apply outside a
-- group -- gating it ourselves would only make the panels dead on a target
-- dummy for no reason.
local function HasAssist()
    if not IsInGroup() then return true end
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

local function IsLeader()
    if not IsInGroup() then return true end
    return UnitIsGroupLeader("player")
end

-- In a RAID, every control on the panel needs leader or assist: ready check,
-- role check, the countdown, convert, disband and the marker buttons are all
-- refused by the server without it. That USED to take the whole feature off
-- the screen in a raid without assist; by request it no longer does -- the
-- panel now stays visible in every group (subject only to Show Mode), and
-- RefreshPermissions is left to dim/disable the individual controls the
-- server would refuse. This function is kept (rather than deleted) so every
-- call site below reads the same way and a future "hide when powerless"
-- toggle has a single place to live again.
local function AssistSuppressed()
    return false
end

-- An optional button's switch, defaulting to shown for an unset profile.
local function ButtonShown(key)
    local p = P()
    return not p or p[key] ~= false
end

-- The pull durations worth a button, in slot order. 0 (and anything below it)
-- means the user turned that slot off.
local function VisiblePullTimes()
    local times = (P() and P().pullTimes) or {}
    local out = {}
    for i = 1, PULL_SLOTS do
        local secs = times[i]
        if secs == nil then secs = PULL_DEFAULTS[i] end
        if secs and secs > 0 then out[#out + 1] = secs end
    end
    return out
end

-------------------------------------------------------------------------------
--  Raid Groups filter -- which subgroups the EllesmereUI Raid Frames draw.
--  This panel is a pure remote control for that addon's own setting; the
--  actual filtering happens over there.
-------------------------------------------------------------------------------

-- Re-resolved on every call: nil while the Raid Frames addon is disabled, and
-- a profile switch repoints .profile underneath.
local function RaidFramesProfile()
    local get = EllesmereUI.Lite and EllesmereUI.Lite.GetAddon
    local a = get and get("EllesmereUIRaidFrames", true)
    return a and a.db and a.db.profile
end

-- Matches how the raid frames themselves read it: absent means unfiltered.
-- Their DEFAULT is groups 1-6 (7 and 8 off), which this row shows as-is --
-- a second default here would be exactly the drift the design forbids.
local function GroupShown(index)
    local p = RaidFramesProfile()
    local vg = p and p.visibleGroups
    return not vg or vg[index] ~= false
end

local function SetGroupShown(index, on)
    local p = RaidFramesProfile()
    local vg = p and p.visibleGroups
    if not vg then return end
    vg[index] = on

    -- Applying this rebuilds secure group headers, which the game forbids in
    -- combat: their own layout bails under lockdown, and their post-combat
    -- pass only re-lays out for roster and size-tier changes, so it would
    -- never pick this up on its own. The setting lands now; the re-render
    -- waits for PLAYER_REGEN_ENABLED.
    if InCombatLockdown() then
        groupsPending = true
    elseif _G._ERF_RefreshAll then
        _G._ERF_RefreshAll()
    end
end

-- Fired on the not-in-group -> in-group edge (see EnsureEvents): a fresh
-- group carries no relationship to whatever an old raid night's filter left
-- behind, so every slot goes back to shown rather than silently hiding
-- frames for a roster the filter was never set up for. Same combat deferral
-- as SetGroupShown, for the same reason.
local function ResetGroupFilter()
    local p = RaidFramesProfile()
    local vg = p and p.visibleGroups
    if not vg then return end
    for i = 1, RAID_GROUPS do vg[i] = true end
    if InCombatLockdown() then
        groupsPending = true
    elseif _G._ERF_RefreshAll then
        _G._ERF_RefreshAll()
    end
end

-- Accent numeral = this group is drawn. The colour is passed in rather than
-- resolved here: the caller repaints eight buttons from one accent read. The
-- border rides the same signal: white while the group is shown, back to the
-- button chrome's normal gray line the moment it is filtered out.
local function PaintRaidGroup(b, shown, ar, ag, ab)
    if shown then
        b._lbl:SetTextColor(ar, ag, ab, 1)
        if b._border and b._border.SetColor then b._border:SetColor(1, 1, 1, 1) end
    else
        b._lbl:SetTextColor(1, 1, 1, 0.35)
        if b._border and b._border.SetColor then b._border:SetColor(BRD_R, BRD_G, BRD_B, BRD_A) end
    end
end

local function MakeRaidGroupButton(parent, index, width)
    -- Declared before the call: the click closure reaches the button through
    -- it, and `local b = ...` would not be in scope inside its own initializer.
    -- Same shape the pull buttons use.
    local b
    b = MakeGroupButton(parent, "", width, function()
        SetGroupShown(index, not GroupShown(index))
        PaintRaidGroup(b, GroupShown(index), EllesmereUI.GetAccentColor())
    end, nil, raidGroupButtons)
    b._lbl:SetText(tostring(index))
    return b
end

-- Repaints all eight, and cuts input when there are no EllesmereUI raid
-- frames to redraw. That is the whole fallback for a user running the
-- Blizzard raid frames (or another addon's) instead.
--
-- Memoized on the state it draws, the same reason RefreshPermissions is: this
-- runs on GROUP_ROSTER_UPDATE, which bursts through a raid night, and nothing
-- it reads changes on that event. `force` is for callers that have to repaint
-- regardless -- Apply, whose accent colour or fonts may have moved underneath.
local lastGroupsMask
local function RefreshRaidGroups(force)
    local p  = RaidFramesProfile()
    local vg = p and p.visibleGroups
    local raid = IsInRaid()

    -- One integer standing for "everything this function would draw": the
    -- eight toggles, whether there is anything to drive at all, and whether
    -- the toggles are even usable right now (raid vs. party/solo).
    local mask, bit = (p and 1 or 0) + (raid and 2 or 0), 4
    for i = 1, RAID_GROUPS do
        if not vg or vg[i] ~= false then mask = mask + bit end
        bit = bit * 2
    end
    if not force and mask == lastGroupsMask then return end
    lastGroupsMask = mask

    -- These toggles change what only THIS client draws, not a real raid
    -- action -- no combat-safety reason to keep them live when they cannot
    -- mean anything, unlike the marker buttons below. A subgroup is a raid
    -- concept; a 5-man party has none to filter.
    local on = p ~= nil and raid
    local ar, ag, ab = EllesmereUI.GetAccentColor()
    for i, b in ipairs(raidGroupButtons) do
        SetButtonEnabled(b, on)
        PaintRaidGroup(b, not vg or vg[i] ~= false, ar, ag, ab)
    end
    if raidGroupsRowLabel then
        raidGroupsRowLabel:SetText(EllesmereUI.L(
            p and RAIDGROUPS_ROW_LABEL or RAIDGROUPS_ROW_NO_RF))
    end
end

-------------------------------------------------------------------------------
--  Make Everyone Assistant -- a raid-only checkbox, not a one-shot button:
--  its own checked state is never stored, only read live off the roster
--  (AllAssistants), so it can never drift from what the raid actually looks
--  like -- someone promoted or demoted outside this panel shows up correctly
--  the next time anything refreshes it.
-------------------------------------------------------------------------------

-- True only once every non-leader member holds assistant (or better). An
-- empty/solo raid (should not happen; you are always a member) reads false
-- rather than vacuously true, so the box never renders checked before there
-- is anyone to have promoted.
local function AllAssistants()
    if not IsInRaid() then return false end
    local n = GetNumGroupMembers()
    if n == 0 then return false end
    for i = 1, n do
        local _, rank = GetRaidRosterInfo(i)
        if rank == 0 then return false end
    end
    return true
end

-- Flips every non-leader member to the target rank. The leader is always
-- skipped -- promoting/demoting them is meaningless (they outrank assistant
-- either way) and PromoteToAssistant on your own leader unit is a no-op at
-- best, so there is nothing to gain by including it.
--
-- Combat-guarded defensively, the same shape as MoveMember in
-- EllesmereUIQoL_RaidGroups.lua: raid-roster functions have turned out to be
-- protected before when the API did not obviously say so (SetRaidSubgroup),
-- so this assumes the same rather than finding out from another bug report.
local function SetEveryoneAssistant(on)
    if InCombatLockdown() then
        EllesmereUI.Print("|cff0cd29fEllesmereUI:|r " ..
            EllesmereUI.L("Raid ranks cannot be changed in combat."))
        return
    end
    local n = GetNumGroupMembers()
    for i = 1, n do
        local _, rank = GetRaidRosterInfo(i)
        if rank == 2 then
            -- leader, skip
        elseif on and rank == 0 then
            PromoteToAssistant("raid" .. i)
        elseif not on and rank == 1 then
            DemoteAssistant("raid" .. i)
        end
    end
end

-- Reads the roster fresh rather than toggling a remembered boolean: called
-- from RefreshPermissions, which already runs on every roster/leadership
-- event, so the box is never more than one event stale.
local function RefreshAssistCheckbox()
    if not assistCheckTex then return end
    assistCheckTex:SetShown(AllAssistants())
end

-- GROUP_ROSTER_UPDATE is one of the chattiest events in a raid -- it bursts on
-- every join, leave and zone-in -- while assist/leader/raid/grouped status
-- changes a handful of times a night. Memo the four inputs and bail when none
-- moved. `force` is for callers that have just built or rebuilt the buttons.
local lastAssist, lastLeader, lastRaid, lastGrouped
local function RefreshPermissions(force)
    local assist, leader, raid, grouped = HasAssist(), IsLeader(), IsInRaid(), IsInGroup()
    if not force and assist == lastAssist and leader == lastLeader
       and raid == lastRaid and grouped == lastGrouped then
        return
    end
    lastAssist, lastLeader, lastRaid, lastGrouped = assist, leader, raid, grouped

    -- HasAssist/IsLeader both read true when solo (see their own header).
    -- These four are real group actions with no meaning outside a group, so
    -- they gate on `grouped` FIRST: assist/leader only count once there is
    -- an actual group to be assist or leader of.
    for _, b in ipairs(groupButtons) do
        local on = grouped and (b.needsLeader and leader or assist)
        -- Convert to Party can't succeed with more than 5 members in the
        -- raid group -- the server just refuses it -- so grey the button out
        -- in that case regardless of leader/assist, the same way the other
        -- buttons grey out for a permission the server would refuse.
        if b == convertButton and raid and GetNumGroupMembers() > 5 then
            on = false
        end
        SetButtonEnabled(b, on)
    end

    -- Secure buttons: cosmetic only, never Enable/Disable (see header).
    -- 0.8 is the grid's resting opacity (hover lifts to 1); 0.4 is the
    -- dim (no permission, or -- world markers only -- not in a group at
    -- all), which also suppresses the hover lift.
    --
    -- Markers are NOT gated on `assist` the way the four buttons above are:
    -- Blizzard only restricts raid target/world markers to leader/assist
    -- inside an actual RAID. In a plain party (or solo), any member can
    -- place them from the native UI, so gating on `assist` there dimmed a
    -- button the server would have honored -- hence `canMark`, which only
    -- checks leader/assist once `raid` is true. Target markers stay usable
    -- outside a raid entirely (marking your own target works solo/party).
    -- World markers still need a group to place for, hence `grouped`.
    local canMark = (not raid) or assist
    for _, b in ipairs(markerButtons) do
        local on = canMark and (b._kind ~= "world" or grouped)
        b._baseAlpha = on and 0.8 or 0.4
        b.icon:SetAlpha(b._baseAlpha)
    end

    if convertButton then
        convertButton._lbl:SetText(raid and EllesmereUI.L("Convert to Party")
                                         or EllesmereUI.L("Convert to Raid"))
    end

    -- Leader-only: unlike Ready Check/Role Check, this one actually requires
    -- the raid leader specifically -- an assistant can promote a single
    -- member from the native raid frames, but not run this bulk toggle.
    if assistCheckRow then
        SetButtonEnabled(assistCheckRow, raid and leader)
        RefreshAssistCheckbox()
    end

    -- The cog itself is never gated here anymore: it always opens the window,
    -- lead/assist or not, so someone can see the roster and have it come alive
    -- the instant they are handed assist. The window enforces its own gate on
    -- what it lets you DO (see ns.RaidGroupsPermitted and the grey-out inside
    -- EllesmereUIQoL_RaidGroups.lua) rather than on whether it can be opened.
end

-------------------------------------------------------------------------------
--  Pull timer
--
--  A pull has to reach the whole raid, not just this client, so the countdown
--  is handed to whichever boss mod is loaded through its published slash
--  handler -- that is the thing that broadcasts the timer to everyone else --
--  and Blizzard's own countdown runs on top for anyone without one.
--
--  Blizzard's countdown travels through chat, so the client refuses it during
--  combat. The boss mod handoff happens first for that reason: it still works
--  there, and losing the in-game countdown is better than losing both.
-------------------------------------------------------------------------------

local function BossModPullHandler()
    return SlashCmdList.BIGWIGSPULL or SlashCmdList.DEADLYBOSSMODSPULL
end

local function ChatLocked()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
       and C_ChatInfo.InChatMessagingLockdown()
end

local function StartPull(secs)
    local handler = BossModPullHandler()
    if handler then handler(tostring(secs)) end
    if ChatLocked() then
        EllesmereUI.Print("|cff0cd29fEllesmereUI:|r " .. EllesmereUI.L("In-game countdown unavailable in combat; the boss mod pull timer still started."))
        return
    end
    C_PartyInfo.DoCountdown(secs)
end

local function StopPull()
    local handler = BossModPullHandler()
    if handler then handler("0") end
    if not ChatLocked() then C_PartyInfo.DoCountdown(0) end
end

-------------------------------------------------------------------------------
--  Group actions
-------------------------------------------------------------------------------

local function DisbandGroup()
    if not IsLeader() then return end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name = GetRaidRosterInfo(i)
            if name and name ~= UnitName("player") then
                C_PartyInfo.UninviteUnit(name)
            end
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            local name = UnitName("party" .. i)
            if name then C_PartyInfo.UninviteUnit(name) end
        end
    end
    C_PartyInfo.LeaveParty()
end

-- The suite's own confirm dialog, not StaticPopup: CONTRIBUTING is explicit
-- that confirmations use ShowConfirmPopup, and it is the one that inherits the
-- panel skin and the scale registry.
local function ConfirmDisband()
    EllesmereUI:ShowConfirmPopup({
        title       = "Disband Group",
        message     = "Disband the group?",
        confirmText = "Disband",
        cancelText  = "Cancel",
        onConfirm   = DisbandGroup,
    })
end

-------------------------------------------------------------------------------
--  Frames (built once, on first non-never Apply -- secure children forbid
--  rebuilding)
-------------------------------------------------------------------------------

-- One secure window shell. Returns the frame; content lives in the plain
-- holders, so the shell owns only chrome (bg, border, title, collapse button)
-- and the visibility state machine.
local function MakeShell(key)
    -- A Button, not a plain Frame: RegisterForClicks/_onclick (the same
    -- secure click path the collapse button and toggle use) only exist on
    -- the Button widget. Content buttons (markers, group buttons, the
    -- collapse corner) sit on top and claim their own clicks first, so this
    -- only ever fires for a click that lands on bare background. Reuses
    -- COLLAPSE_SNIPPET verbatim -- same minimize-to-icon behavior as the
    -- corner button, just reachable from anywhere on the panel.
    local f = CreateFrame("Button", "EllesmereUIRaidTools" .. key, UIParent,
                          "SecureHandlerStateTemplate, SecureHandlerClickTemplate")
    f:SetWidth(PANEL_W)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:Hide()
    f:RegisterForClicks("RightButtonUp")
    f:SetAttribute("_onclick", COLLAPSE_SNIPPET)

    -- The Window Skins dress (see the block above).
    SkinPanelBg(f)
    SkinPanelBorder(f)

    -- Visibility state: see the header. "apply" is the ONLY place this frame
    -- is shown or hidden.
    f:SetAttribute("enabled", true)
    f:SetAttribute("visible", false)
    f:SetAttribute("override", "")
    f:SetAttribute("expanded", true)
    f:SetAttribute("startexpanded", true)
    f:SetAttribute("apply", [[
        if not self:GetAttribute("enabled") then
            self:Hide()
            return
        end
        local ov = self:GetAttribute("override")
        local vis
        if ov == "show" then
            vis = true
        elseif ov == "hide" then
            vis = false
        else
            vis = self:GetAttribute("visible")
        end
        if vis and self:GetAttribute("expanded") then
            self:Show()
        else
            self:Hide()
        end
    ]])
    -- A driver transition is a context change: it reclaims control from any
    -- manual override and re-seeds the collapsed/expanded form. The icon has
    -- no state template of its own (click templates do not dispatch _onstate),
    -- so each shell fans the verdict out to it -- both shells stamping the
    -- same values is idempotent.
    f:SetAttribute("_onstate-euirt_vis", [[
        local vis = (newstate == "show")
        self:SetAttribute("visible", vis)
        self:SetAttribute("override", "")
        self:SetAttribute("expanded", self:GetAttribute("startexpanded"))
        self:RunAttribute("apply")
        local icon = self:GetFrameRef("icon")
        if icon then
            icon:SetAttribute("visible", vis)
            icon:SetAttribute("override", "")
            icon:SetAttribute("expanded", self:GetAttribute("startexpanded"))
            icon:RunAttribute("apply")
        end
    ]])

    -- White title, vertically centered in the black band (the skins' title
    -- treatment; the accent stays on interactions, not chrome). Re-pointed by
    -- ApplyLayout to clear whichever corner Open Direction puts the collapse
    -- button in.
    local fs = TrackFont(f, EllesmereUI.MakeFont(f, 12, nil, 1, 1, 1), 12)
    fs:SetPoint("LEFT", f, "TOPLEFT", PAD, -TOPBAR_H / 2)  -- re-pointed by ApplyLayout
    fs:SetText(EllesmereUI.L(SECTION_LABEL[key]))
    shellTitle[key] = fs

    -- Collapse button: small secure corner control riding the title band,
    -- only meaningful (and only shown -- ApplyLayout owns that) while Default
    -- to Collapsed Icon is on. Wears the skins' button chrome.
    local col = CreateFrame("Button", nil, f, "SecureHandlerClickTemplate")
    col:SetSize(14, 14)
    col:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -TOPBAR_H / 2)  -- re-pointed by ApplyLayout
    col:RegisterForClicks("AnyDown")
    SkinButtonChrome(col)
    local colFs = TrackFont(f, EllesmereUI.MakeFont(col, 14, nil, 1, 1, 1), 14)
    colFs:SetPoint("CENTER", col, "CENTER", 0, 1)
    colFs:SetText("-")
    colFs:SetAlpha(0.7)
    col:SetScript("OnEnter", function() colFs:SetAlpha(1) end)
    col:SetScript("OnLeave", function() colFs:SetAlpha(0.7) end)
    col:SetAttribute("_onclick", COLLAPSE_SNIPPET)
    f._collapseBtn = col

    sections[key] = f
    fontOwners[#fontOwners + 1] = f
    return f
end

-- Where the Group & Pull content actually lands. Re-run on every Apply, and
-- the ONLY writer of GROUP_CONTENT_H -- which button is on screen is a
-- setting, so positions, widths and the holder height all follow the profile
-- rather than the build.
--
-- Everything it touches is a plain frame, and Apply is out-of-combat only, so
-- this is an ordinary re-point with no lockdown story. It must run BEFORE
-- ApplyLayout, which sizes the shells from GROUP_CONTENT_H.
local function LayoutGroupContent()
    if not groupHolder then return end
    local f = groupHolder

    -- Row plan first, geometry second: collect what is actually shown, two
    -- action buttons per row in the fixed order below, so a hidden button
    -- closes the gap instead of leaving a hole. A row that ends up with a
    -- single button takes the full width.
    local rows, pair = {}, {}
    local function Add(b)
        pair[#pair + 1] = b
        if #pair == 2 then rows[#rows + 1] = pair; pair = {} end
    end
    Add(readyButton)
    if ButtonShown("showRoleCheck") then Add(roleButton) end
    if ButtonShown("showConvert")   then Add(convertButton) end
    if ButtonShown("showDisband")   then Add(disbandButton) end
    if #pair > 0 then rows[#rows + 1] = pair end

    -- Pull row: the slots left above 0, sharing the row with Stop. The
    -- duration lives on the button (the click closure reads it back), so the
    -- surviving durations simply move onto the leading buttons.
    --
    -- All three at 0 drops the row entirely, Stop included: a Stop button
    -- alone is a pull-timer row with no pull timer.
    local times = VisiblePullTimes()
    if #times > 0 then
        local pull = {}
        for i, secs in ipairs(times) do
            local b = pullButtons[i]
            b.secs = secs
            b._lbl:SetText(tostring(secs))
            pull[i] = b
        end
        pull[#pull + 1] = stopButton
        rows[#rows + 1] = pull
    end

    -- Hide first, show what the plan placed: anything the switches dropped
    -- stops at this line.
    for _, b in ipairs(groupButtons) do b:Hide() end

    -- Make Everyone Assistant sits above this flow, fixed at the top of the
    -- holder (see BuildGroupContent) -- reserve its row before laying out
    -- the buttons below it.
    local y = -(ROW_H + ROW_GAP)
    for _, row in ipairs(rows) do
        local n = #row
        local w = (PANEL_W - PAD * 2 - ROW_GAP * (n - 1)) / n
        for i, b in ipairs(row) do
            b:SetWidth(w)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (w + ROW_GAP) * (i - 1), y)
            b:Show()
        end
        y = y - ROW_H - ROW_GAP
    end
    y = y + ROW_GAP   -- the last row's trailing gap is not content

    GROUP_CONTENT_H = -y
    f:SetHeight(GROUP_CONTENT_H)
end

-- Group & Pull content, in its own plain holder so one-window mode can treat
-- it uniformly with the markers holder. Creation only -- the buttons are born
-- unplaced at full-row width, and LayoutGroupContent puts them where the
-- settings say (MakeGroupButton runs labels through L itself).
local function BuildGroupContent()
    groupHolder = CreateFrame("Frame", nil, sections.Group)
    groupHolder:SetWidth(PANEL_W)
    fontOwners[#fontOwners + 1] = groupHolder
    local f = groupHolder
    local full = PANEL_W - PAD * 2

    -- Make Everyone Assistant: first row, right under the title, fixed in
    -- place (not part of LayoutGroupContent's flow). Whole-row button (not
    -- just the box) so the label is as clickable as the tick -- same
    -- reasoning as the pull/marker rows' generous hit targets.
    assistCheckRow = CreateFrame("Button", nil, f)
    assistCheckRow:SetSize(PANEL_W - PAD * 2, ROW_H)
    assistCheckRow:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, 0)
    local chkBox = CreateFrame("Frame", nil, assistCheckRow)
    chkBox:SetSize(ASSIST_CHK_SZ, ASSIST_CHK_SZ)
    chkBox:SetPoint("LEFT", assistCheckRow, "LEFT", 0, 0)
    local chkFill = chkBox:CreateTexture(nil, "BACKGROUND")
    chkFill:SetColorTexture(BTN_R, BTN_G, BTN_B, BTN_A)
    chkFill:SetAllPoints(chkBox)
    EllesmereUI.MakeBorder(chkBox, BRD_R, BRD_G, BRD_B, BRD_A, EllesmereUI.PP)
    -- The classic Blizzard checkbox tick, oversized 1px past the box on
    -- every edge: the source art carries its own padding, so an exact fit
    -- reads as a smaller, off-center mark.
    assistCheckTex = chkBox:CreateTexture(nil, "OVERLAY")
    assistCheckTex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    assistCheckTex:SetPoint("TOPLEFT", chkBox, "TOPLEFT", -1, 1)
    assistCheckTex:SetPoint("BOTTOMRIGHT", chkBox, "BOTTOMRIGHT", 1, -1)
    assistCheckTex:Hide()
    local chkHover = assistCheckRow:CreateTexture(nil, "HIGHLIGHT")
    chkHover:SetColorTexture(1, 1, 1, 0.05)
    chkHover:SetAllPoints(assistCheckRow)
    local chkLbl = TrackFont(f, EllesmereUI.MakeFont(assistCheckRow, 11, nil, 1, 1, 1), 11)
    chkLbl:SetPoint("LEFT", chkBox, "RIGHT", 6, 0)
    chkLbl:SetJustifyH("LEFT")
    chkLbl:SetText(EllesmereUI.L("Make Everyone Assistant"))
    assistCheckRow:SetScript("OnClick", function()
        SetEveryoneAssistant(not AllAssistants())
        RefreshAssistCheckbox()
    end)
    -- MakeGroupButton runs labels through L itself. All four action buttons
    -- are born unplaced at full-row width; LayoutGroupContent re-flows the
    -- survivors (per the showRoleCheck/showConvert/showDisband switches)
    -- starting below this fixed checkbox row.
    readyButton = MakeGroupButton(f, "Ready Check", full, function() DoReadyCheck() end)
    roleButton  = MakeGroupButton(f, "Role Check", full, function() InitiateRolePoll() end)

    convertButton = MakeGroupButton(f, "Convert to Raid", full, function()
        if IsInRaid() then C_PartyInfo.ConvertToParty() else C_PartyInfo.ConvertToRaid() end
    end, true)

    disbandButton = MakeGroupButton(f, "Disband", full, function()
        ConfirmDisband()
    end, true)

    for i = 1, PULL_SLOTS do
        -- The pull duration lives on the button and changes at runtime, so
        -- the click reads it through the closure.
        local b
        b = MakeGroupButton(f, "", full, function() StartPull(b.secs) end)
        pullButtons[i] = b
    end
    stopButton = MakeGroupButton(f, "Stop", full, StopPull)

    -- A height right away: BuildAll has callers (the slash command, unlock
    -- mode) that reach the shells without going through Apply.
    LayoutGroupContent()
end

-- Row order matches how they are used: unit markers first, ground markers
-- under them. Labels reach L as variables (see the SECTIONS comment).
local MARKER_ROWS = {
    { kind = "target", label = "Target" },
    { kind = "world",  label = "World"  },
}

local function BuildMarkersContent()
    markersHolder = CreateFrame("Frame", nil, sections.Markers)
    markersHolder:SetWidth(PANEL_W)
    fontOwners[#fontOwners + 1] = markersHolder
    local f = markersHolder
    local y = 0

    -- 8 markers + a clear button per row, evenly spread across the width.
    local step = (PANEL_W - PAD * 2 - MARKER_SZ) / 8
    for r, row in ipairs(MARKER_ROWS) do
        local lbl = TrackFont(f, EllesmereUI.MakeFont(f, 9, nil, 1, 1, 1), 9)
        lbl:SetAlpha(0.55)
        lbl:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
        lbl:SetText(EllesmereUI.L(row.label))
        y = y - MARKER_LBL_H - 2

        for i = 0, 8 do
            local b = MakeMarkerButton(f, i == 8 and 0 or (i + 1), row.kind)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + step * i, y)
        end
        y = y - MARKER_SZ
        if r < #MARKER_ROWS then y = y - ROW_GAP * 2 end
    end

    -- Raid Groups row: last row of the panel, right after Target and World --
    -- one toggle per subgroup, showing/hiding it on the EllesmereUI Raid
    -- Frames. The sub-label doubles as the no-raid-frames explanation --
    -- RefreshRaidGroups owns its text.
    y = y - ROW_GAP * 2
    raidGroupsRowLabel = TrackFont(f, EllesmereUI.MakeFont(f, 9, nil, 1, 1, 1), 9)
    raidGroupsRowLabel:SetAlpha(0.55)
    raidGroupsRowLabel:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    raidGroupsRowLabel:SetText(EllesmereUI.L(RAIDGROUPS_ROW_LABEL))
    y = y - MARKER_LBL_H - 2

    local gw = (PANEL_W - PAD * 2 - (RAID_GROUPS - 1) * ROW_GAP) / RAID_GROUPS
    for i = 1, RAID_GROUPS do
        local gb = MakeRaidGroupButton(f, i, gw)
        gb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (gw + ROW_GAP) * (i - 1), y)
    end
    y = y - ROW_H

    MARKERS_CONTENT_H = -y
    f:SetHeight(MARKERS_CONTENT_H)
end

-- The collapsed-state square: bg + border + the icon, expanding on click.
-- A click template (not a state template) -- it cannot dispatch _onstate, so
-- the shells fan the driver verdict to it (see MakeShell).
local function BuildCollapsedIcon()
    iconBtn = CreateFrame("Button", "EllesmereUIRaidToolsIcon", UIParent,
                          "SecureHandlerClickTemplate")
    iconBtn:SetSize(ICON_SZ, ICON_SZ)
    iconBtn:SetFrameStrata("MEDIUM")
    iconBtn:SetClampedToScreen(true)
    iconBtn:RegisterForClicks("AnyDown")
    iconBtn:Hide()
    -- Rides the Group shell's saved position with no bookkeeping of its own:
    -- anchoring to a hidden frame is fine, the anchor resolves through its
    -- points.
    iconBtn:SetPoint("TOPLEFT", nil, "TOPLEFT", 0, 0)  -- re-pointed at build

    -- The button IS the art: full-bleed image at full opacity, no chrome and
    -- no tooltip.
    local tex = iconBtn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(iconBtn)
    tex:SetTexture(COLLAPSED_ICON_TEX)

    -- Hover whitens the art by 10%: the SAME image additively at 0.1 on the
    -- native HIGHLIGHT layer (auto shown on mouseover, no scripts). Re-using
    -- the image keeps the lift inside its alpha channel -- a plain white ADD
    -- rect would glow the transparent corners too. Vertex color cannot do
    -- this; it only multiplies downward.
    local hl = iconBtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(iconBtn)
    hl:SetTexture(COLLAPSED_ICON_TEX)
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.5)

    iconBtn:SetAttribute("enabled", true)
    iconBtn:SetAttribute("visible", false)
    iconBtn:SetAttribute("override", "")
    iconBtn:SetAttribute("expanded", true)
    iconBtn:SetAttribute("startexpanded", true)
    iconBtn:SetAttribute("apply", [[
        if not self:GetAttribute("enabled") then
            self:Hide()
            return
        end
        local ov = self:GetAttribute("override")
        local vis
        if ov == "show" then
            vis = true
        elseif ov == "hide" then
            vis = false
        else
            vis = self:GetAttribute("visible")
        end
        if vis and not self:GetAttribute("expanded") then
            self:Show()
        else
            self:Hide()
        end
    ]])
    iconBtn:SetAttribute("_onclick", EXPAND_SNIPPET)
end

-- The cog that opens EllesmereUIQoL_RaidGroups.lua's group-composition
-- window. Plain (not secure) and NOT combat-gated: SetRaidSubgroup/
-- SwapRaidSubgroup carry no lockdown restriction, and that other window is
-- what actually acts on the roster -- this is just its door. Always clickable,
-- lead/assist or not: the window itself opens read-only without either and
-- greys itself in the instant it is lost, then lights back up the instant it
-- is gained (see ns.RaidGroupsPermitted in EllesmereUIQoL_RaidGroups.lua) --
-- so gating the door as well would only hide the one place that shows it is
-- about to become usable.
-- Same chrome and size as the shell's own close button (14x14, SkinButtonChrome,
-- a single font glyph) so the two read as one matched pair riding the same
-- corner -- "+" opens the roster, "-" right beside it closes the panel.
local function BuildRaidGroupsCog()
    local b = CreateFrame("Button", nil, sections.Group)
    b:SetSize(COG_SZ, COG_SZ)
    b:SetFrameLevel(sections.Group:GetFrameLevel() + 5)
    SkinButtonChrome(b)
    -- "+" is drawn a size larger than "-"/"*" (16 vs 14) and nudged down
    -- (0 vs 1) because the font's own "+" glyph sits smaller and higher on
    -- its line than "-" or "*" do -- same SetPoint/SetSize as its neighbors
    -- would leave it looking thin and off-center even though the numbers
    -- matched.
    local lbl = TrackFont(sections.Group, EllesmereUI.MakeFont(b, 16, nil, 1, 1, 1), 16)
    lbl:SetPoint("CENTER", b, "CENTER", 0, 0)
    lbl:SetText("+")
    lbl:SetAlpha(0.7)
    b:SetScript("OnEnter", function(self)
        lbl:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(EllesmereUI.L("Raid Groups"))
        GameTooltip:AddLine(EllesmereUI.L("Opens the group composition window to view and rearrange raid subgroups."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        lbl:SetAlpha(0.7)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function()
        if ns.ShowRaidGroupsWindow then ns.ShowRaidGroupsWindow() end
    end)
    b._lbl = lbl
    raidGroupsCogBtn = b
end

-- Rides the cog's own inward side, one gap further into the panel (see
-- ApplyLayout's positioning pass below). Not gated on rank the way the cog
-- is: EllesmereUIQoL_RaidCheck.lua's own ns.ShowRaidCheck already refuses to
-- open for someone without lead/assist (unless "Show Without Lead or Assist"
-- is on), so a second permission check here would only disagree with that
-- one under an option flip mid-session.
local function BuildRaidCheckButton()
    local b = CreateFrame("Button", nil, sections.Group)
    b:SetSize(COG_SZ, COG_SZ)
    b:SetFrameLevel(sections.Group:GetFrameLevel() + 5)
    SkinButtonChrome(b)
    local lbl = TrackFont(sections.Group, EllesmereUI.MakeFont(b, 14, nil, 1, 1, 1), 14)
    lbl:SetPoint("CENTER", b, "CENTER", 0, -3)
    lbl:SetText("*")
    lbl:SetAlpha(0.7)
    b:SetScript("OnEnter", function(self)
        lbl:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(EllesmereUI.L("Raid Check"))
        GameTooltip:AddLine(EllesmereUI.L("Re-runs the check and opens its window, even without a ready check."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        lbl:SetAlpha(0.7)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function()
        if ns.ShowRaidCheck then ns.ShowRaidCheck() end
    end)
    b._lbl = lbl
    raidCheckBtn = b
end

-- Flask/Food/Repair/Rune/Vantus report buttons: left-click prints who is
-- missing it (or, for Repair, everyone's durability percentage) to this
-- client's own chat frame only; right-click posts the same thing to /raid
-- or /party depending on the current group. Small title-bar riders, same family
-- as the Raid Groups cog and Raid Check button, but with the full name on
-- each instead of a single glyph -- so every button is sized to its own
-- measured label (see ApplyLayout) rather than a shared fixed width. Not
-- gated on lead/assist -- reading auras and durability someone volunteered
-- is not an action that needs rank -- and, unlike Convert/Disband, NOT
-- greyed out during a boss pull either: reporting a status line mid-fight
-- carries no game-state risk, so these stay clickable through combat and
-- encounters (see RefreshReportButtons).
local function BuildReportButtons()
    for _, def in ipairs(REPORT_COLUMNS) do
        local b = CreateFrame("Button", nil, sections.Group)
        b:SetHeight(COG_SZ)
        b:SetFrameLevel(sections.Group:GetFrameLevel() + 5)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        SkinButtonChrome(b)
        local lbl = TrackFont(sections.Group, EllesmereUI.MakeFont(b, 8, nil, 1, 1, 1), 8)
        lbl:SetPoint("CENTER", b, "CENTER", 0, 0)
        lbl:SetText(EllesmereUI.L(def.label or def.title))
        lbl:SetAlpha(0.7)
        -- A first pass now (ApplyLayout re-measures and resizes every pass,
        -- since a Global Font change moves GetStringWidth without a reload).
        b:SetWidth(math.ceil((lbl:GetStringWidth() or 20) + REPORT_BTN_PAD * 2))
        b:SetScript("OnEnter", function(self)
            lbl:SetAlpha(1)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(EllesmereUI.L(def.title))
            GameTooltip:AddLine(EllesmereUI.L("Left Click: print to your own chat only."), 1, 1, 1)
            GameTooltip:AddLine(EllesmereUI.L("Right Click: report to raid/party chat."), 1, 1, 1)
            if def.key == "durability" then
                GameTooltip:AddLine(EllesmereUI.L("Lists anyone at 90% or below, worst first."), 0.7, 0.7, 0.7, true)
            else
                GameTooltip:AddLine(EllesmereUI.L("Lists who is missing it."), 0.7, 0.7, 0.7, true)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            lbl:SetAlpha(0.7)
            GameTooltip:Hide()
        end)
        b:SetScript("OnClick", function(_, button)
            if ns.ReportConsumable then
                ns.ReportConsumable(def.key, button == "RightButton")
            end
        end)
        b._lbl = lbl
        reportBtns[#reportBtns + 1] = b
    end
end

-- No combat gate: reporting who is missing a flask/food/rune/vantus, or
-- everyone's durability, is read-only chat output, not an action the game
-- restricts in combat -- so these always stay enabled, in or out of a boss
-- encounter.
local function RefreshReportButtons()
    for _, b in ipairs(reportBtns) do
        SetButtonEnabled(b, true)
    end
end

local function BuildAll()
    if sections.Group then return end
    MakeShell("Group")
    MakeShell("Markers")
    BuildGroupContent()
    BuildMarkersContent()
    BuildCollapsedIcon()
    BuildRaidGroupsCog()
    BuildRaidCheckButton()
    BuildReportButtons()
    iconBtn:ClearAllPoints()
    iconBtn:SetPoint("TOPLEFT", sections.Group, "TOPLEFT", 0, 0)

    -- Keybind target. Shown (a hidden button cannot take a CLICK binding) but
    -- 1px, transparent and parked off-screen. It flips everything together
    -- from one computed value, so the pieces can never drift apart.
    toggleButton = CreateFrame("Button", "EllesmereUIRaidToolsToggle", UIParent,
                               "SecureHandlerClickTemplate")
    toggleButton:SetSize(1, 1)
    toggleButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -100, -100)
    toggleButton:SetAlpha(0)
    toggleButton:RegisterForClicks("AnyDown")
    toggleButton:SetAttribute("count", #SECTION_KEYS)
    toggleButton:SetAttribute("_onclick", TOGGLE_SNIPPET)

    -- Frame refs: the toggle, the icon and each collapse button all reach the
    -- same set; the shells reach the icon for the _onstate fan-out.
    for i, key in ipairs(SECTION_KEYS) do
        local shell = sections[key]
        toggleButton:SetFrameRef("s" .. i, shell)
        shell:SetFrameRef("icon", iconBtn)
        shell:SetAttribute("count", #SECTION_KEYS)
        for j, k2 in ipairs(SECTION_KEYS) do
            shell:SetFrameRef("s" .. j, sections[k2])
        end
        shell._collapseBtn:SetAttribute("count", #SECTION_KEYS)
        for j, k2 in ipairs(SECTION_KEYS) do
            shell._collapseBtn:SetFrameRef("s" .. j, sections[k2])
        end
        shell._collapseBtn:SetFrameRef("icon", iconBtn)
        iconBtn:SetFrameRef("s" .. i, shell)
    end
    toggleButton:SetFrameRef("icon", iconBtn)
    iconBtn:SetAttribute("count", #SECTION_KEYS)
end

-------------------------------------------------------------------------------
--  Layout / position / mode
-------------------------------------------------------------------------------

-- Menu Grow Direction -> which corner of the primary shell the collapsed
-- icon occupies. The icon is the piece the user parks, so the corner it
-- rides decides which way the windows appear to grow from it on expand:
-- icon at TOPLEFT = windows extend down-right (the original behaviour),
-- icon at BOTTOMLEFT = up-right, and so on. See GROW_DIRECTION_CORNER /
-- AnchorCorner above -- title insets, the collapse buttons, the Raid
-- Groups cog and the Raid Check button all share this same corner.

-- Show-as arrangement. OOC only (Apply gates); the holders are plain frames,
-- so the re-parent is an ordinary SetParent.
local function ApplyLayout()
    local p = P()
    local showAs = ShowAs()
    local winGroup, winMarkers = sections.Group, sections.Markers

    local collapseUI = p and p.collapsedIcon ~= false
    winGroup._collapseBtn:SetShown(collapseUI)
    -- Two Windows: only Group & Pull carries the collapse control -- one
    -- button folds the whole feature, and a second on Markers would just be
    -- a duplicate. Markers keeps its own ONLY when it is the lone window.
    local markersHasBtn = collapseUI and showAs ~= "two"
    winMarkers._collapseBtn:SetShown(markersHasBtn)

    -- The close (collapse) button rides the SAME corner Open Direction
    -- anchors the collapsed icon to, so the panel closes at the exact spot
    -- it opened from -- see AnchorCorner's header. Each shell that shows the
    -- button gets a title inset (TOPLEFT only -- every other corner already
    -- lands clear of the title text) and, for a BOTTOM corner, a little extra
    -- height so the button never sits over the last content row. The Group
    -- shell alone also carries the Raid Groups cog riding the button's inward
    -- side, so its own reserve is a little wider.
    -- Report row: measured fresh every pass (not cached at build time) so a
    -- Global Font change is picked up without a UI reload -- see
    -- BuildReportButtons for REPORT_BTN_PAD/REPORT_GAP.
    local reportReserve = 0
    for _, b in ipairs(reportBtns) do
        local w = math.ceil((b._lbl:GetStringWidth() or 20) + REPORT_BTN_PAD * 2)
        b:SetWidth(w)
        b._reportWidth = w
        reportReserve = reportReserve + REPORT_GAP + w
    end

    local corner = AnchorCorner()
    local isBottom = corner == "BOTTOMLEFT" or corner == "BOTTOMRIGHT"
    local function Reserve(hasBtn, extra)
        local titleReserve  = (hasBtn and corner == "TOPLEFT")
            and (BTN_TITLE_RESERVE + (extra or 0)) or PAD
        local bottomReserve = (hasBtn and isBottom) and BTN_BOTTOM_RESERVE or 0
        return titleReserve, bottomReserve
    end
    local groupTitleReserve, groupBottomReserve = Reserve(collapseUI, GROUP_COG_RESERVE + reportReserve)
    local markersTitleReserve, markersBottomReserve = Reserve(markersHasBtn)

    if showAs == "one" then
        shellTitle.Group:SetText(EllesmereUI.L(COMBINED_LABEL))
        groupHolder:SetShown(true)
        groupHolder:SetParent(winGroup)
        groupHolder:ClearAllPoints()
        groupHolder:SetPoint("TOPLEFT", winGroup, "TOPLEFT", 0, -CONTENT_TOP)
        markersHolder:SetShown(true)
        markersHolder:SetParent(winGroup)
        markersHolder:ClearAllPoints()
        markersHolder:SetPoint("TOPLEFT", winGroup, "TOPLEFT", 0,
            -CONTENT_TOP - GROUP_CONTENT_H - ROW_GAP * 2)
        winGroup:SetHeight(CONTENT_TOP + GROUP_CONTENT_H + ROW_GAP * 2
            + MARKERS_CONTENT_H + PAD + groupBottomReserve)
    else
        -- Every split mode parents each holder to its own shell; which shells
        -- actually SHOW is ApplyVisibility's call (the enabled attribute).
        shellTitle.Group:SetText(EllesmereUI.L(SECTION_LABEL.Group))
        groupHolder:SetParent(winGroup)
        groupHolder:SetShown(true)
        groupHolder:ClearAllPoints()
        groupHolder:SetPoint("TOPLEFT", winGroup, "TOPLEFT", 0, -CONTENT_TOP)
        winGroup:SetHeight(CONTENT_TOP + GROUP_CONTENT_H + PAD + groupBottomReserve)

        markersHolder:SetParent(winMarkers)
        markersHolder:SetShown(true)
        markersHolder:ClearAllPoints()
        markersHolder:SetPoint("TOPLEFT", winMarkers, "TOPLEFT", 0, -CONTENT_TOP)
        winMarkers:SetHeight(CONTENT_TOP + MARKERS_CONTENT_H + PAD + markersBottomReserve)
    end

    -- Title insets: pushed clear of the collapse button on whichever shell
    -- carries one and opens from TOPLEFT; PAD everywhere else.
    shellTitle.Group:ClearAllPoints()
    shellTitle.Group:SetPoint("LEFT", winGroup, "TOPLEFT", groupTitleReserve, -TOPBAR_H / 2)
    shellTitle.Markers:ClearAllPoints()
    shellTitle.Markers:SetPoint("LEFT", winMarkers, "TOPLEFT", markersTitleReserve, -TOPBAR_H / 2)

    -- Collapse buttons: both re-anchored to the shared corner every pass, even
    -- on the shell whose button is currently hidden -- harmless while hidden,
    -- and keeps the two shells from ever disagreeing about where it lands.
    local off = COLLAPSE_OFFSET[corner]
    winGroup._collapseBtn:ClearAllPoints()
    winGroup._collapseBtn:SetPoint(corner, winGroup, corner, off[1], off[2])
    winMarkers._collapseBtn:ClearAllPoints()
    winMarkers._collapseBtn:SetPoint(corner, winMarkers, corner, off[1], off[2])

    -- Raid Groups cog: same corner as the close button, one gap further
    -- INTO the panel (toward horizontal center) rather than off the edge --
    -- "LEFT" corners grow the offset, "RIGHT" corners shrink it, so the cog
    -- always lands beside the close button instead of past the shell's edge.
    if raidGroupsCogBtn then
        local isLeftCorner = corner:find("LEFT") ~= nil
        local inward = COG_GAP + 14   -- 14 = the close button's own width
        local cogDx = off[1] + (isLeftCorner and inward or -inward)
        raidGroupsCogBtn:ClearAllPoints()
        raidGroupsCogBtn:SetPoint(corner, winGroup, corner, cogDx, off[2])
    end

    -- Raid Check button: same corner, one further gap inward past the cog --
    -- close, then Raid Groups, then Raid Check, reading outward to inward.
    if raidCheckBtn then
        local isLeftCorner = corner:find("LEFT") ~= nil
        local inward = (COG_GAP + 14) + (RAIDCHECK_GAP + COG_SZ)
        local rcDx = off[1] + (isLeftCorner and inward or -inward)
        raidCheckBtn:ClearAllPoints()
        raidCheckBtn:SetPoint(corner, winGroup, corner, rcDx, off[2])
    end

    -- Report row: five more riders past Raid Check, same corner, same
    -- outward-to-inward reading (close, Raid Groups, Raid Check, then
    -- Flask/Food/Repair/Rune/Vantus) -- each sized to its own measured
    -- label (see above) rather than a fixed width, so the full name fits.
    if #reportBtns > 0 then
        local isLeftCorner = corner:find("LEFT") ~= nil
        local edge = (COG_GAP + 14) + (RAIDCHECK_GAP + COG_SZ) + COG_SZ + REPORT_GAP
        for _, b in ipairs(reportBtns) do
            local dx = off[1] + (isLeftCorner and edge or -edge)
            b:ClearAllPoints()
            b:SetPoint(corner, winGroup, corner, dx, off[2])
            edge = edge + b._reportWidth + REPORT_GAP
        end
    end

    -- The collapsed icon rides the shell the mode actually shows -- Markers-
    -- only anchors (and scales, see Apply) to the Markers shell, everything
    -- else to Group & Pull -- at whichever corner Menu Grow Direction (growDir)
    -- names, the same corner its shell's collapse button just took.
    local hostShell = (showAs == "markers") and winMarkers or winGroup
    iconBtn:ClearAllPoints()
    iconBtn:SetPoint(corner, hostShell, corner, 0, 0)

    -- Heights just moved: re-crop the backdrop art so it covers instead of
    -- stretches (the skins hook SetHeight for this; our heights only ever
    -- change right here, so a direct call is the whole hook).
    if winGroup._bgFit then winGroup._bgFit() end
    if winMarkers._bgFit then winMarkers._bgFit() end
end

-- Positions round-trip through unlock mode's CENTER/CENTER convention.
--
-- That pairing is not decoration: for an odd-height frame the stored centre
-- ends in .5, and ApplyCenterPosition subtracts the live half-height so the
-- edges land back on whole pixels. Applying the stored value with a plain
-- SetPoint skips that and leaves the frame a pixel off -- visible only after
-- the snap tool, because a normal drag is converted on the way in and a
-- snapped one is not.
local function DefaultPos(key)
    -- Unpositioned installs park the whole feature near the screen edge that
    -- matches its opening corner (a small margin off the edges); two-window
    -- mode stacks Markers away from Group & Pull in whichever direction the
    -- shell actually grows. A saved position always wins over this.
    local MARGIN = 20
    local corner = AnchorCorner()
    local isTop  = corner:find("TOP") ~= nil
    local isLeft = corner:find("LEFT") ~= nil
    -- TOP grows down (more negative y as later windows stack); BOTTOM grows
    -- up (more positive y). LEFT margins are positive x off the left edge;
    -- RIGHT margins are negative x off the right edge.
    local vSign = isTop and -1 or 1
    local xSign = isLeft and 1 or -1

    local vOff = vSign * MARGIN
    if key == "Markers" then
        vOff = vOff + vSign * (sections.Group:GetHeight() * WindowScale() + ROW_GAP)
    end
    -- Screen-space margin converted into the frame's own scaled units.
    local s = WindowScale()
    return { point = corner, relPoint = corner, x = (xSign * MARGIN) / s, y = vOff / s }
end

local function ApplySectionPosition(key)
    local f = sections[key]
    if not f then return end
    if InCombatLockdown() then applyPending = true; return end

    local pos = ((P() and P().pos) or {})[key] or DefaultPos(key)
    if EllesmereUI.ApplyCenterPosition
       and pos.point == "CENTER" and pos.relPoint == "CENTER" then
        -- Skips anchor-linked elements itself, and defers its own combat case
        -- for protected frames. FALSE means it could not resolve a live frame
        -- for this key -- fall through to the plain path, exactly as unlock
        -- mode's own caller does.
        if EllesmereUI.ApplyCenterPosition(UNLOCK_KEY .. key, pos) then return end
    end

    -- Anything not in that convention is a default or a pre-conversion value.
    if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(UNLOCK_KEY .. key) then
        return
    end
    f:ClearAllPoints()
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
end

local function ApplyPositions()
    -- While an unlock session is open UNLOCK MODE owns these frames: it moves
    -- them live and only writes the result on Save & Exit. A settings pass
    -- landing mid-session (the options panel hiding/showing flips the preview,
    -- and a combat-deferred Apply completes on PLAYER_REGEN_ENABLED) would drag
    -- the window back to the last SAVED spot -- and because Save & Exit derives
    -- the value it stores from the frame's LIVE bounds, the drag is then
    -- written back as the old position and lost for good. Same guard Action
    -- Bars, Aura Reminders and the Cooldown Manager already carry.
    if EllesmereUI._unlockActive then return end

    -- Each shell is positioned only when the Show as choice can put it on
    -- screen; One Window and Only Group & Pull ride pos.Group, Only Markers
    -- rides pos.Markers.
    local showAs = ShowAs()
    if showAs ~= "markers" then ApplySectionPosition("Group") end
    if showAs == "two" or showAs == "markers" then ApplySectionPosition("Markers") end
end

-- The whole replacement for the old shared-visibility machinery: two literal
-- driver strings keyed by mode. [group] is any group; [group:raid] raid only.
local MODE_DRIVERS = {
    raid  = "[group:raid] show; hide",
    group = "[group] show; hide",
}

-- Reached only from Apply, which has already returned if we are in combat.
local function ApplyVisibility()
    local p = P()
    local mode = Mode()
    local driver = MODE_DRIVERS[mode]
    -- The out-of-combat settle for the state a driver will not re-fire
    -- (registering one only fires _onstate on a CHANGE). Always mode has no
    -- driver at all: the settle IS its entire visibility source.
    local visNow = false
    if mode == "raid" then
        visNow = IsInRaid()
    elseif mode == "group" then
        visNow = IsInGroup()
    elseif mode == "always" then
        visNow = true
    end

    -- Which SHELLS may show, straight from Show as: the Group shell is the
    -- window everywhere except Markers-only; the Markers shell exists only in
    -- Two Windows and Markers-only.
    --
    -- `suppressed` is always false now (see AssistSuppressed) -- kept as a
    -- multiplier here rather than removed so a future gate can drop back in
    -- without touching this shape again.
    local showAs = ShowAs()
    local suppressed = AssistSuppressed()
    local shellOn = {
        Group   = showAs ~= "markers" and not suppressed,
        Markers = (showAs == "two" or showAs == "markers") and not suppressed,
    }
    -- One seed for every show (see header): Default to Collapsed When Shown.
    -- With the toggle off the seed is "expanded" and the icon never shows.
    local startExpanded = not (p and p.collapsedIcon ~= false)

    -- Settings preview (the TBB-placeholder arrangement): while the Raid
    -- Tools page is in front, the windows are forced shown and FULLY EXPANDED
    -- so every settings change is visible as it lands, and the drivers stay
    -- unregistered so a group transition cannot collapse or hide the thing
    -- being configured mid-edit. Only the LIVE state is forced; the seeds
    -- keep their configured values for when the preview ends.
    local expandedNow = startExpanded
    if previewOn then
        driver = nil
        visNow = true
        expandedNow = true
    end

    for _, key in ipairs(SECTION_KEYS) do
        local f = sections[key]
        local on = shellOn[key] and true or false

        f:SetAttribute("enabled", on)
        f:SetAttribute("visible", visNow)
        f:SetAttribute("override", "")
        f:SetAttribute("startexpanded", startExpanded)
        f:SetAttribute("expanded", expandedNow)

        UnregisterStateDriver(f, "euirt_vis")
        if on and driver then
            RegisterStateDriver(f, "euirt_vis", driver)
        end
    end

    -- The icon represents the whole feature; every Show as choice shows
    -- something, so it is on while the mode is active and the assist gate is
    -- open. With it shut the keybind and the slash command go quiet too --
    -- both run the secure snippets, and those refuse a disabled frame.
    iconBtn:SetAttribute("enabled", not suppressed)
    iconBtn:SetAttribute("visible", visNow)
    iconBtn:SetAttribute("override", "")
    iconBtn:SetAttribute("startexpanded", startExpanded)
    iconBtn:SetAttribute("expanded", expandedNow)

    -- What is now ON SCREEN, for the roster handler to compare against.
    lastSuppressed = suppressed

    -- Run the snippets rather than re-deciding in Lua: attributes are set
    -- first so "apply" sees them.
    if SecureHandlerExecute then
        for _, key in ipairs(SECTION_KEYS) do
            SecureHandlerExecute(sections[key], RUN_APPLY)
        end
        SecureHandlerExecute(iconBtn, RUN_APPLY)
    end

    ApplyMouseoverFade()
end

-- Seeds every shell's (and the collapsed icon's) alpha for the current
-- Visibility() choice: full opacity whenever it isn't "mouseover" (or the
-- settings preview is forcing full opacity), otherwise whichever of them the
-- cursor is currently over. Called from here (any settings pass -- mode,
-- showAs, visibility, a driver transition) AND from the mouseoverTicker poll
-- below, so a Visibility change lands immediately instead of waiting for the
-- next hover.
function ApplyMouseoverFade()
    local faded = (Visibility() == "mouseover") and not previewOn
    for _, key in ipairs(SECTION_KEYS) do
        local f = sections[key]
        if f then
            f:SetAlpha((not faded or f:IsMouseOver()) and 1 or 0)
        end
    end
    if iconBtn then
        iconBtn:SetAlpha((not faded or iconBtn:IsMouseOver()) and 1 or 0)
    end
end

-- Mouseover visibility fade: a throttled OnUpdate poll rather than
-- OnEnter/OnLeave on the shells or the icon -- a child button (marker,
-- collapse, etc.) stealing mouse focus would otherwise fire an OnLeave while
-- the cursor is still over the parent. Module-scope and always running is
-- cheap: it no-ops immediately whenever nothing has been built yet or
-- Visibility() isn't "mouseover".
local mouseoverTicker = CreateFrame("Frame")
do
    local sinceLast = 0
    mouseoverTicker:SetScript("OnUpdate", function(self, elapsed)
        if not sections.Group or Visibility() ~= "mouseover" or previewOn then return end
        sinceLast = sinceLast + elapsed
        if sinceLast < 0.1 then return end
        sinceLast = 0
        ApplyMouseoverFade()
    end)
end

-- Auto-Minimize: once the full windows have sat expanded (any shell
-- actually shown, not the collapsed icon) with the cursor OFF them for
-- AutoMinimizeDelay() seconds straight, collapse them back to the icon --
-- the exact effect the corner collapse button already produces, just fired
-- by a timer instead of a click. The cursor sitting over any shown shell
-- pauses the count entirely (checked with IsMouseOver's bounding-box test,
-- the same one ApplyMouseoverFade uses, so a child button -- marker,
-- collapse, etc. -- stealing mouse focus still reads as "over the panel");
-- moving off starts the delay over from zero rather than resuming a
-- partial count, so a player who's been reading the panel on and off never
-- gets surprised by it vanishing moments after they last looked away.
-- Reuses COLLAPSE_SNIPPET verbatim via SecureHandlerExecute on Group's
-- collapse button, which already carries frame refs to every section and
-- the icon (see BuildAll), so this needs no state of its own on any secure
-- frame.
--
-- A throttled OnUpdate poll, the same shape as the mouseover ticker above:
-- cheap when idle (nothing built yet, the feature off, the settings preview
-- forcing things open, or the windows simply not expanded right now) and it
-- only ever touches protected state through SecureHandlerExecute, which
-- silently refuses to run in combat -- so an expiry reached mid-fight just
-- waits, the same way every other options-driven change here defers behind
-- combat lockdown, and the next tick tries again once combat ends.
local autoMinimizeTicker = CreateFrame("Frame")
do
    local sinceLast   = 0
    local idleElapsed = 0   -- seconds accumulated while expanded and un-hovered

    autoMinimizeTicker:SetScript("OnUpdate", function(self, elapsed)
        if not sections.Group or Mode() == "never" or previewOn
           or EllesmereUI._unlockActive or not AutoMinimize() then
            idleElapsed = 0
            return
        end
        sinceLast = sinceLast + elapsed
        if sinceLast < 0.5 then return end
        local tick = sinceLast
        sinceLast = 0

        local isExpanded, isHovered = false, false
        for _, key in ipairs(SECTION_KEYS) do
            local f = sections[key]
            if f and f:IsShown() then
                isExpanded = true
                if f:IsMouseOver() then isHovered = true end
            end
        end

        if not isExpanded or isHovered then
            idleElapsed = 0
            return
        end
        idleElapsed = idleElapsed + tick
        if idleElapsed < AutoMinimizeDelay() then return end
        if InCombatLockdown() or not SecureHandlerExecute then return end
        SecureHandlerExecute(sections.Group._collapseBtn, COLLAPSE_SNIPPET)
        idleElapsed = 0
    end)
end

-- Toggle Raid Tools key: profile-stored, applied as an override binding on
-- the secure toggle button -- the exact arrangement Action Bars uses for
-- Toggle Action Bar. Pressing the bound key is a hardware click,
-- so the toggle itself works IN combat; only (re)binding defers.
local function ApplyToggleKeybind()
    if not toggleButton then return end
    ClearOverrideBindings(toggleButton)
    local p = P()
    local k = p and p.toggleKey
    -- The gate takes the binding with it rather than leaving a key that eats
    -- its own keypress: the snippet would refuse a disabled frame, and an
    -- override binding swallows whatever the key does otherwise.
    if k and k ~= "" and Mode() ~= "never" and not AssistSuppressed() then
        SetOverrideBindingClick(toggleButton, false, k, "EllesmereUIRaidToolsToggle")
    end
end

-------------------------------------------------------------------------------
--  Lifecycle
--
--  Nothing exists until the mode first leaves "never": no frames, no events,
--  no bindings, no unlock rows. Apply() is the single entry point.
-------------------------------------------------------------------------------

-- The assist gate is Lua's, so a promotion, a demotion or a raid you join
-- without assist has to bring Apply back around -- no state driver will do it
-- for us. Compared against what ApplyVisibility last put on screen, because
-- GROUP_ROSTER_UPDATE bursts and Apply is not free.
--
-- In combat Apply parks itself behind applyPending, which leaves lastSuppressed
-- untouched: the next roster event re-enters here and parks again, and
-- PLAYER_REGEN_ENABLED finishes the job. That is the module's standard
-- deferral, not an omission.
local function RefreshAssistGate()
    if AssistSuppressed() ~= lastSuppressed then Apply() end
end

-- Events live only while the feature is active (or while a combat-deferred
-- Apply is pending, since PLAYER_REGEN_ENABLED is what completes it). The
-- frame itself is created on first need and reused.
local ev
local function EnsureEvents()
    if not ev then
        ev = CreateFrame("Frame")
        ev:SetScript("OnEvent", function(_, event)
            -- Pending work FIRST, before the mode gate: a switch TO "never"
            -- deferred by combat must complete even though the profile
            -- already reads never -- swallowing it here is how panels get
            -- stranded on screen.
            -- A group-filter click during combat wrote the setting but could
            -- not rebuild the raid frames. Runs before the Apply branch,
            -- which returns without reaching it.
            if event == "PLAYER_REGEN_ENABLED" and groupsPending then
                groupsPending = false
                if _G._ERF_RefreshAll then _G._ERF_RefreshAll() end
            end
            if event == "PLAYER_REGEN_ENABLED" and applyPending then
                Apply()
                return
            end
            -- Not-in-group -> in-group edge: a freshly formed or freshly
            -- joined group, not just another roster shuffle within the same
            -- one (GROUP_ROSTER_UPDATE fires constantly for those, and
            -- wasInGroup already being true skips them). Every group starts
            -- with every subgroup shown.
            if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
                local inGroup = IsInGroup()
                if inGroup and not wasInGroup then
                    ResetGroupFilter()
                end
                wasInGroup = inGroup
            end
            if Mode() == "never" then return end
            RefreshPermissions()
            RefreshRaidGroups()
            RefreshAssistGate()
            RefreshReportButtons()
        end)
    end
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PARTY_LEADER_CHANGED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("ENCOUNTER_START")
    ev:RegisterEvent("ENCOUNTER_END")
end
local function DropEvents()
    if ev then ev:UnregisterAllEvents() end
end

-- Unlock-mode movers, registered once, on first activation. getFrame
-- returning nil keeps an element out of unlock mode, which is also how
-- one-window mode collapses the feature to a single element: the Markers
-- entry vanishes and the Group entry moves the combined window via pos.Group.
local unlockRegistered
local function RegisterUnlock()
    if unlockRegistered then return end
    local MK = EllesmereUI.MakeUnlockElement
    if not MK then return end
    unlockRegistered = true

    local elements = {}
    for i, key in ipairs(SECTION_KEYS) do
        elements[#elements + 1] = MK({
            key      = UNLOCK_KEY .. key,
            label    = SECTION_LABEL[key],
            group    = "Raid Tools",
            order    = 540 + i,
            noResize = true,
            getFrame = function()
                if Mode() == "never" then return nil end
                -- Nothing to move while the assist gate has the whole feature
                -- off the screen -- same opt-out as the modes below.
                if AssistSuppressed() then return nil end
                -- Offer exactly the shells the Show as choice puts on screen:
                -- One Window / Only Group & Pull = the Group element alone,
                -- Two Windows = both, Only Markers = the Markers element alone.
                local showAs = ShowAs()
                if key == "Group" and showAs == "markers" then return nil end
                if key == "Markers" and showAs ~= "two" and showAs ~= "markers" then return nil end
                BuildAll()
                return sections[key]
            end,
            getSize  = function()
                -- Unlock mode sizes the mover overlay in UIParent units, so
                -- the Window Scale has to be folded in here -- GetWidth is the
                -- frame's own (unscaled) size.
                local s = WindowScale()
                local f = sections[key]
                if f then return f:GetWidth() * s, f:GetHeight() * s end
                return PANEL_W * s, 60 * s
            end,
            savePos = function(_, point, relPoint, x, y)
                if not point then return end
                local p = P(); if not p then return end
                -- Unlock mode hands us two conventions: a normal drag arrives
                -- already converted to CENTER/CENTER, a snapped one arrives
                -- raw. Converting here makes both identical --
                -- ConvertToCenterPos passes an already-CENTER value through
                -- untouched, so the drag path is unaffected.
                if EllesmereUI.ConvertToCenterPos then
                    point, relPoint, x, y =
                        EllesmereUI.ConvertToCenterPos(UNLOCK_KEY .. key, point, relPoint, x, y)
                end
                -- Direct index, no `p.pos = p.pos or {}` reseed: DB_DEFAULTS
                -- guarantees the table, and under a Spec Overrides capture
                -- proxy the reseed stores a proxy into the real profile (the
                -- hazard the P() comment documents). Writing THROUGH p.pos is
                -- proxy-safe; storing it back is not.
                if not p.pos then return end
                p.pos[key] = { point = point, relPoint = relPoint, x = x, y = y }
                if not EllesmereUI._unlockActive then ApplySectionPosition(key) end
            end,
            loadPos  = function() return ((P() and P().pos) or {})[key] end,
            clearPos = function()
                local p = P(); if p and p.pos then p.pos[key] = nil end
            end,
            applyPos = function() ApplySectionPosition(key) end,
        })
    end
    if #elements > 0 then
        EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIQoL")
    end
end

-- Options-page entry point, and the completion target for combat-deferred
-- work. Every path below writes secure attributes, drivers, bindings or
-- geometry on protected frames -- ALL blocked in lockdown, the switch to
-- "never" included (SetAttribute is as protected as Hide). So in combat the
-- whole request is parked behind applyPending, with the REGEN listener
-- guaranteed alive to finish it.
function Apply()
    if InCombatLockdown() then
        applyPending = true
        EnsureEvents()
        return
    end
    applyPending = false

    -- The settings preview builds and shows even on Never: the page being in
    -- front means the user is configuring the thing, and an invisible subject
    -- makes every control feel dead. Preview off restores the true teardown.
    if Mode() == "never" and not previewOn then
        if sections.Group then
            for _, key in ipairs(SECTION_KEYS) do
                local f = sections[key]
                UnregisterStateDriver(f, "euirt_vis")
                f:SetAttribute("enabled", false)
                f:SetAttribute("override", "")
                f:Hide()
            end
            iconBtn:SetAttribute("enabled", false)
            iconBtn:Hide()
            ClearOverrideBindings(toggleButton)
        end
        -- Fully off and nothing pending: no reason to keep hearing roster
        -- spam. Never-activated sessions never created the frame at all.
        DropEvents()
        return
    end

    EnsureEvents()
    RegisterUnlock()
    BuildAll()
    -- Before ApplyLayout: it sizes the shells from GROUP_CONTENT_H, which the
    -- hidden buttons and the 0-second pull slots move.
    LayoutGroupContent()
    ApplyLayout()
    -- One Window Scale for everything the feature draws.
    local scale = WindowScale()
    sections.Group:SetScale(scale)
    sections.Markers:SetScale(scale)
    iconBtn:SetScale(scale)
    -- One Strata for every shell and the collapsed icon.
    local strata = Strata()
    sections.Group:SetFrameStrata(strata)
    sections.Markers:SetFrameStrata(strata)
    iconBtn:SetFrameStrata(strata)
    ApplyPositions()
    ApplyVisibility()
    ApplyToggleKeybind()
    ApplyFonts()
    RefreshPermissions(true)
    RefreshRaidGroups(true)
    RefreshReportButtons()
end
_G._EUI_RaidTools_Apply = Apply

-- Settings-page preview switch (see ApplyVisibility). A global rather than an
-- ns export on purpose: the QoL page dispatcher in EUI_QoL_Options.lua has no
-- ns capture, and it is the one that must end the preview when another QoL
-- page builds. Same convention as _EUI_RaidTools_Apply.
_G._EUI_RaidTools_Preview = function(on)
    on = on and true or false
    if previewOn == on then return end
    previewOn = on
    Apply()
end

-------------------------------------------------------------------------------
--  Slash command
-------------------------------------------------------------------------------

-- Same snippet as the keybind, entered through SecureHandlerExecute -- which
-- insecure code may only do out of combat, hence the message below. This
-- deliberately does NOT go through toggleButton:Click(): the button is
-- registered for "AnyDown" only, and a bare Click() simulates an up event, so
-- the handler would never fire. The keybind keeps the hardware path because a
-- real click is the only thing that can run the snippet during combat.
local function ToggleOutOfCombat()
    if toggleButton and SecureHandlerExecute then
        SecureHandlerExecute(toggleButton, TOGGLE_SNIPPET)
    end
end

SLASH_EUIRAIDTOOLS1 = "/euiraid"
SlashCmdList["EUIRAIDTOOLS"] = function()
    if Mode() == "never" then
        EllesmereUI.Print("|cff0cd29fEllesmereUI:|r " .. EllesmereUI.L("Raid Tools is disabled in the EllesmereUI options."))
        return
    end
    if InCombatLockdown() then
        EllesmereUI.Print("|cff0cd29fEllesmereUI:|r " .. EllesmereUI.L("Raid Tools cannot be toggled by slash command in combat -- use the keybind."))
        return
    end
    -- The snippet would refuse anyway (enabled is false while the gate is
    -- shut); saying so beats a slash command that looks broken.
    if AssistSuppressed() then
        EllesmereUI.Print("|cff0cd29fEllesmereUI:|r " .. EllesmereUI.L("Raid Tools is hidden in a raid without leader or assist -- none of its buttons work there."))
        return
    end
    BuildAll()
    ToggleOutOfCombat()
end

-------------------------------------------------------------------------------
--  Init -- same shape as the other QoL features: take the shared QoL DB handle
--  on PLAYER_LOGIN, publish it, then start. Apply() is a no-op for anyone on
--  the default "never" mode: no frames, no events, no unlock rows.
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not (EllesmereUI and EllesmereUI.Lite and EllesmereUI.Lite.NewDB) then return end
    db = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", DB_DEFAULTS, true)
    _G._EUI_RaidTools_DB = function() return db end
    Apply()
end)
