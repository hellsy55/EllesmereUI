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
--                 which grows to fit and titles itself "Raid Tools"; ONE unlock
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
ns.BREAK_DEFAULT = 300                -- 5 minutes, stored in seconds
ns.BREAK_MAX = 1800                   -- 30 minutes

-- The collapse ("close") button sits at the same literal corner Open
-- Direction anchors the collapsed icon to, so the panel closes at the exact
-- spot it opened from. The whole corner-control row uses the same 10px edge
-- inset as the content rows and the same 22px height as ordinary action
-- buttons, keeping Minimize / Raid Groups / Raid Check visually aligned with
-- the rows immediately inside the shell in every grow direction.
local CORNER_BTN_SZ      = ROW_H
local BTN_MARGIN         = PAD
local BTN_TITLE_RESERVE  = BTN_MARGIN + CORNER_BTN_SZ + 6
local BTN_BOTTOM_RESERVE = CORNER_BTN_SZ + ROW_GAP * 2
local GROUP_TOP_RESERVE  = BTN_MARGIN + CORNER_BTN_SZ + ROW_GAP * 2
local COLLAPSE_OFFSET = {
    TOPLEFT     = {  BTN_MARGIN, -BTN_MARGIN },
    TOPRIGHT    = { -BTN_MARGIN, -BTN_MARGIN },
    BOTTOMLEFT  = {  BTN_MARGIN,  BTN_MARGIN },
    BOTTOMRIGHT = { -BTN_MARGIN,  BTN_MARGIN },
}

-- Raid Groups cog: opens the group-composition window (EllesmereUIQoL_
-- RaidGroups.lua). Lives only on the Group & Pull shell, riding the inward
-- side of the close button -- same corner, one gap further into the panel --
-- so it never competes with Open Direction for its own spot.
local COG_SZ  = CORNER_BTN_SZ
local COG_GAP = 4
-- Raid Check and Invite Tools continue inward from the Raid Groups cog. This
-- makes Invite Tools sit immediately to the RIGHT of Raid Check while the
-- menu grows right, and immediately to its LEFT while the menu grows left.
-- The title reserve covers all three riders.
local RAIDCHECK_GAP = COG_GAP
local INVITETOOLS_GAP = COG_GAP
local GROUP_COG_RESERVE = (COG_GAP + COG_SZ) + (RAIDCHECK_GAP + COG_SZ)
                        + (INVITETOOLS_GAP + COG_SZ) + 6  -- three riders + clearance

-- Consumable/repair reports live on their own full-width content row, kept
-- separate from the corner chrome (collapse / Raid Groups / Raid Check / Invite Tools).
-- They read left-to-right in the same order shown in the Raid Tools UI and
-- share the exact row sizing/gap math used by Ready/Disband and Pull Timer.
local REPORT_COLUMNS = {
    { key = "food",       title = "Food" },
    { key = "flask",      title = "Flask" },
    { key = "durability", title = "Repair" },
    { key = "vantus",     title = "Vantus" },
    { key = "rune",       title = "Rune" },
}

-- Make Everyone Assistant checkbox: fixed row beneath the report-button row.
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
local runtime = {}             -- lazily-created runtime state
runtime.roleColumns = {
    { role = "TANK",    label = "Tank" },
    { role = "HEALER",  label = "Heal" },
    { role = "DAMAGER", label = "DPS"  },
}
local sections = {}            -- key -> shell frame
local shellTitle = {}          -- key -> title fontstring
local shellTitleFont = {}      -- key -> tracked font entry (combined title can be slightly larger)
local groupHolder, markersHolder   -- plain content holders (see header)
local iconBtn                  -- collapsed-state square
local raidGroupsCogBtn          -- opens the Raid Groups composition window (Group shell only)
local raidCheckBtn              -- re-runs and shows the Raid Check window on demand (Group shell only)
local inviteToolsBtn            -- opens Invite Tools (Group shell only)
local reportBtns = {}           -- Flask/Food/Repair/Rune/Vantus report buttons (Group shell only)
local assistCheckRow, assistCheckTex   -- Make Everyone Assistant row (Group shell, raid-only)
-- Markers are fixed at build; the Group & Pull height follows the settings and
-- is re-computed by LayoutGroupContent on every Apply.
local GROUP_CONTENT_H, MARKERS_CONTENT_H
local Apply                    -- forward: the event handler closes over it
local ApplyMouseoverFade       -- forward: ApplyVisibility and the mouseover ticker close over it

-- ONE representation of each secure decision, run from both paths.
--
-- The keybind clicks the button, which is the only thing that works during combat. Out
-- of combat the same snippet is run through SecureHandlerExecute instead of being
-- re-implemented in Lua. EUI_RaidFrames_BossFrames.lua does exactly this, for exactly this
-- reason: the driver manager only fires the attribute handlers on value CHANGES, so a
-- reapply with unchanged states would otherwise never run.
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
    local entry = { fs = fs, size = size }
    t[#t + 1] = entry
    return fs, entry
end
local function SetTrackedFontSize(entry, size)
    if not entry then return end
    entry.size = size
    local path, _, flags = entry.fs:GetFont()
    if path then entry.fs:SetFont(path, size, flags or "") end
end
local function ApplyFonts()
    local path = EllesmereUI.GetFontPath(FONT_KEY)
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
local markerRowButtons = { target = {}, world = {} }
local markerRowLabels = {}
local pullButtons = {}         -- fixed set of 3; only the ones above 0s show
local raidGroupButtons = {}    -- plain buttons, gated on the raid frames only
runtime.roleCountButtons = {}  -- display-only raid role counters
local raidGroupsRowLabel
local COMBINED_MARKERS_TOP = 0 -- y-offset of the marker block inside combined Group holder
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
        -- Opt-in world-marker bindings. Empty defaults mean enabling Quick
        -- Fire alone never claims a key.
        quickFire         = false,
        quickFirePlaceKey = false,
        quickFireUndoKey  = false,
        quickFireClearKey = false,
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
        -- buttonVisibility ("always" | "mouseover"): same choice for the
        -- collapsed icon alone. Deliberately left unseeded: unset follows
        -- visibility (see ButtonVisibility), so older profiles are unchanged.
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
        -- Invite Tools state. Raid Tools owns the launcher in EUI, so no
        -- separate minimap launcher settings are needed here.
        inviteTools = {
            Current            = 1,
            ListScale          = 1,
            List1              = "",
            AutoInvite         = true,
            AutoInviteInterval = 30,
            AutoAcceptShared   = false,
            AutoAcceptFriendly = false,
            SyncRaid            = true,
            ShowNicknames       = true,
            CustomWhisper       = "Send invites for the shared list, please",
            ClearOnBossKill     = true,
            ShareIgnoreSeconds = 30,
            Width              = 430,
            Height             = 436,
            PositionX          = 0,
            PositionY          = 50,
            Unlocked           = false,
            History            = {},
            HiddenFriends      = {},
        },
        -- Three slots is a LAYOUT choice (they fill one row beside Stop), not
        -- a security constraint -- the pull buttons are plain, only the marker
        -- buttons are secure. Growing the count later means growing the panel,
        -- nothing more.
        --
        -- 0 means "no button": the slot drops out of the row and the survivors
        -- share the width. All three at 0 takes the row away entirely, Stop
        -- included (see LayoutGroupContent).
        pullTimes     = { PULL_DEFAULTS[1], PULL_DEFAULTS[2], PULL_DEFAULTS[3] },
        -- Break is stored in seconds as well. 0 removes its row; values are
        -- clamped to 30 minutes when read so old/manual profiles cannot push
        -- an invalid duration into a boss-mod timer.
        breakTime     = ns.BREAK_DEFAULT,
        -- Optional controls compact around anything the user hides. Pings and
        -- Difficulty are leader-only at runtime; role counts only render
        -- while the player is actually in a raid group.
        showPings     = true,
        showDifficulty = true,
        showRoleCheck = true,
        showConvert   = true,
        showDisband   = true,
        showRoles     = true,
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

-- The Raid Tools Button Visibility choice: the collapsed icon's own fade,
-- independent of the panels. Unset falls back to the panel choice so
-- profiles saved before the split keep the look they had.
local function ButtonVisibility()
    local p = P()
    local v = p and p.buttonVisibility
    if v ~= "always" and v ~= "mouseover" then return Visibility() end
    return v
end
ns.ButtonVisibility = ButtonVisibility

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
    markerRowButtons[kind][#markerRowButtons[kind] + 1] = b
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

function runtime.BreakTime()
    local secs = P() and tonumber(P().breakTime)
    if secs == nil then secs = ns.BREAK_DEFAULT end
    secs = math.floor((secs + 30) / 60) * 60
    if secs < 0 then secs = 0 end
    if secs > ns.BREAK_MAX then secs = ns.BREAK_MAX end
    return secs
end

function runtime.RolesShown()
    return ButtonShown("showRoles") and IsInRaid()
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
--  Raid role counts -- raid-only display row kept at the marker edge nearest
--  Break in the combined window. These are assigned group roles, not specialization guesses.
-------------------------------------------------------------------------------

function runtime.RefreshRoleCounts(force)
    local visible = runtime.RolesShown()
    local layoutChanged = runtime.lastRolesVisible ~= nil and visible ~= runtime.lastRolesVisible
    runtime.lastRolesVisible = visible

    if visible then
        local counts = { TANK = 0, HEALER = 0, DAMAGER = 0 }
        local maxRaid = _G.MAX_RAID_MEMBERS or 40
        for i = 1, maxRaid do
            local name, _, _, _, _, _, _, _, _, _, _, role = GetRaidRosterInfo(i)
            if name and role then
                local secret = _G.issecretvalue and _G.issecretvalue(role)
                if not secret and counts[role] ~= nil then
                    counts[role] = counts[role] + 1
                end
            end
        end
        for i, def in ipairs(runtime.roleColumns) do
            local b = runtime.roleCountButtons[i]
            if b and b._lbl then
                b._lbl:SetText(EllesmereUI.L(def.label) .. " " .. tostring(counts[def.role] or 0))
            end
        end
    end

    return not force and layoutChanged
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
        return false
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
    return true
end

-- Reads the roster fresh rather than storing a separate checkbox value. It
-- is refreshed directly from roster/role events as well as permission passes,
-- so promotions or demotions made here or elsewhere cannot leave it stale.
local function RefreshAssistCheckbox()
    if not assistCheckTex then return end
    assistCheckTex:SetShown(AllAssistants())
end

-------------------------------------------------------------------------------
--  Leader controls: ping restrictions and dungeon/raid difficulty.
--  Both use the same modern menu API as Blizzard's Compact Raid Manager.
-------------------------------------------------------------------------------

function runtime.ShowPingMenu(button)
    -- This Raid Tools control is intentionally raid-leader-only. Keep the
    -- click guard identical to the visual permission gate below so it stays
    -- visibly unavailable in parties and for non-leaders.
    if not IsInRaid() or not UnitIsGroupLeader("player") or InCombatLockdown() then return end
    if not (MenuUtil and MenuUtil.CreateContextMenu and C_PartyInfo.GetRestrictPings
            and C_PartyInfo.SetRestrictPings and Enum and Enum.RestrictPingsTo) then
        return
    end

    MenuUtil.CreateContextMenu(button, function(_, root)
        root:SetTag("EUI_RAID_TOOLS_RESTRICT_PINGS")
        local function IsSelected(value)
            return C_PartyInfo.GetRestrictPings() == value
        end
        local function SetSelected(value)
            if InCombatLockdown() or not IsInRaid() or not UnitIsGroupLeader("player") then return end
            local newValue = IsSelected(value) and Enum.RestrictPingsTo.None or value
            C_PartyInfo.SetRestrictPings(newValue)

            -- Match Blizzard's own Compact Raid Manager behavior: radio
            -- selections close the menu, then the next open reads the
            -- authoritative server-backed value from GetRestrictPings().
            -- Forcing MenuResponse.Refresh here refreshes synchronously,
            -- before the restriction has necessarily propagated, which can
            -- redraw the old selection and make the control look stale.
        end

        root:CreateRadio(_G.NONE or "None", IsSelected, SetSelected, Enum.RestrictPingsTo.None)
        root:CreateRadio(_G.RAID_MANAGER_RESTRICT_PINGS_TO_LEAD or "Leader Only",
            IsSelected, SetSelected, Enum.RestrictPingsTo.Lead)
        root:CreateRadio(_G.RAID_MANAGER_RESTRICT_PINGS_TO_ASSIST or "Leader & Assistants",
            IsSelected, SetSelected, Enum.RestrictPingsTo.Assist)
        root:CreateRadio(_G.RAID_MANAGER_RESTRICT_PINGS_TO_TANKS_HEALERS or "Tanks & Healers",
            IsSelected, SetSelected, Enum.RestrictPingsTo.TankHealer)
    end)
end

function runtime.DifficultyIDs()
    local ids = _G.DifficultyUtil and _G.DifficultyUtil.ID
    return ids or {
        DungeonNormal = 1, DungeonHeroic = 2, DungeonMythic = 23,
        PrimaryRaidNormal = 14, PrimaryRaidHeroic = 15, PrimaryRaidMythic = 16,
    }
end

function runtime.UsesRaidDifficulty()
    -- Raid difficulty belongs only to an actual raid group. Parties and solo
    -- always read/write the dungeon difficulty, so converting between party
    -- and raid also changes what the button reports without carrying the
    -- previous group's difficulty type across the transition.
    return IsInGroup() and IsInRaid()
end

function runtime.DifficultySuffix()
    local ids = runtime.DifficultyIDs()
    if runtime.UsesRaidDifficulty() then
        local util = _G.DifficultyUtil
        if util and util.DoesCurrentRaidDifficultyMatch then
            if util.DoesCurrentRaidDifficultyMatch(ids.PrimaryRaidMythic) then return "M" end
            if util.DoesCurrentRaidDifficultyMatch(ids.PrimaryRaidHeroic) then return "H" end
            if util.DoesCurrentRaidDifficultyMatch(ids.PrimaryRaidNormal) then return "N" end
        end
        local id = GetRaidDifficultyID and GetRaidDifficultyID()
        if id == ids.PrimaryRaidMythic then return "M" end
        if id == ids.PrimaryRaidHeroic or id == 5 or id == 6 then return "H" end
        if id == ids.PrimaryRaidNormal or id == 3 or id == 4 then return "N" end
    else
        local id = GetDungeonDifficultyID and GetDungeonDifficultyID()
        if id == ids.DungeonMythic then return "M" end
        if id == ids.DungeonHeroic then return "H" end
        if id == ids.DungeonNormal then return "N" end
    end
end

function runtime.RefreshDifficultyLabel()
    if not runtime.difficultyButton or not runtime.difficultyButton._lbl then return end
    local suffix = runtime.DifficultySuffix()
    local text = EllesmereUI.L("Difficulty")
    runtime.difficultyButton._lbl:SetText(suffix and (text .. " (" .. suffix .. ")") or text)
end

function runtime.ShowDifficultyMenu(button)
    -- Difficulty can be changed while solo. Once grouped, only the group
    -- leader may change it, matching Blizzard's own difficulty controls.
    if not IsLeader() or InCombatLockdown() then return end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end

    MenuUtil.CreateContextMenu(button, function(_, root)
        root:SetTag("EUI_RAID_TOOLS_DIFFICULTY")
        local ids = runtime.DifficultyIDs()
        local util = _G.DifficultyUtil

        if runtime.UsesRaidDifficulty() then
            local function IsSelected(id)
                if util and util.DoesCurrentRaidDifficultyMatch then
                    return util.DoesCurrentRaidDifficultyMatch(id)
                end
                return GetRaidDifficultyID and GetRaidDifficultyID() == id
            end
            local function SetSelected(id)
                if InCombatLockdown() or not UnitIsGroupLeader("player") then return end
                if _G.SetRaidDifficulties then
                    _G.SetRaidDifficulties(true, id)
                elseif SetRaidDifficultyID then
                    SetRaidDifficultyID(id)
                end
                runtime.RefreshDifficultyLabel()
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, runtime.RefreshDifficultyLabel)
                end
            end
            local data = {
                { ids.PrimaryRaidNormal, _G.PLAYER_DIFFICULTY1 or "Normal" },
                { ids.PrimaryRaidHeroic, _G.PLAYER_DIFFICULTY2 or "Heroic" },
                { ids.PrimaryRaidMythic, _G.PLAYER_DIFFICULTY6 or "Mythic" },
            }
            for _, item in ipairs(data) do
                local radio = root:CreateRadio(item[2], IsSelected, SetSelected, item[1])
                if util and util.IsRaidDifficultyEnabled then
                    radio:SetEnabled(util.IsRaidDifficultyEnabled(item[1]))
                end
            end
        else
            local function IsSelected(id)
                return GetDungeonDifficultyID and GetDungeonDifficultyID() == id
            end
            local function SetSelected(id)
                if InCombatLockdown() or not IsLeader() then return end
                if SetDungeonDifficultyID then SetDungeonDifficultyID(id) end
                runtime.RefreshDifficultyLabel()
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, runtime.RefreshDifficultyLabel)
                end
            end
            local data = {
                { ids.DungeonNormal, _G.PLAYER_DIFFICULTY1 or "Normal" },
                { ids.DungeonHeroic, _G.PLAYER_DIFFICULTY2 or "Heroic" },
                { ids.DungeonMythic, _G.PLAYER_DIFFICULTY6 or "Mythic" },
            }
            for _, item in ipairs(data) do
                local radio = root:CreateRadio(item[2], IsSelected, SetSelected, item[1])
                if util and util.IsDungeonDifficultyEnabled then
                    radio:SetEnabled(util.IsDungeonDifficultyEnabled(item[1]))
                end
            end
        end
    end)
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

        -- Pings is raid-leader-only. Difficulty remains usable while solo,
        -- and once grouped it requires the group leader. Both use the exact
        -- same disabled treatment as Make Everyone Assistant (alpha + mouse
        -- input), so their state is visually unambiguous instead of merely
        -- refusing the click.
        if b == runtime.pingButton then
            on = raid and leader
        elseif b == runtime.difficultyButton then
            on = leader
        end

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
    runtime.RefreshDifficultyLabel()

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

function runtime.BossModBreakHandler()
    return SlashCmdList["break"] or SlashCmdList.BIGWIGSBREAK
        or SlashCmdList.DEADLYBOSSMODSBREAK
end

function runtime.StartBreak(secs)
    secs = tonumber(secs)
    if not secs or secs <= 0 then return end
    secs = math.floor((secs + 30) / 60) * 60
    if secs > ns.BREAK_MAX then secs = ns.BREAK_MAX end
    if IsEncounterInProgress and IsEncounterInProgress() then
        EllesmereUI.Print("|cff0cd29fEllesmereUI:|r " .. EllesmereUI.L("Break timer unavailable during an encounter."))
        return
    end

    local handler = runtime.BossModBreakHandler()
    if not handler then
        EllesmereUI.Print("|cff0cd29fEllesmereUI:|r " .. EllesmereUI.L("Break timer requires BigWigs or DBM."))
        return
    end
    handler(tostring(secs / 60))
end

function runtime.BreakLabel(secs)
    return EllesmereUI.L("Break") .. " (" .. tostring(secs / 60) .. "m)"
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
    local fs, fsFont = TrackFont(f, EllesmereUI.MakeFont(f, 12, nil, 1, 1, 1), 12)
    fs:SetPoint("LEFT", f, "TOPLEFT", PAD, -TOPBAR_H / 2)  -- re-pointed by ApplyLayout
    fs:SetText(EllesmereUI.L(SECTION_LABEL[key]))
    shellTitle[key] = fs
    shellTitleFont[key] = fsFont

    -- Collapse button: small secure corner control riding the title band,
    -- only meaningful (and only shown -- ApplyLayout owns that) while Default
    -- to Collapsed Icon is on. Wears the skins' button chrome.
    local col = CreateFrame("Button", nil, f, "SecureHandlerClickTemplate")
    col:SetSize(CORNER_BTN_SZ, CORNER_BTN_SZ)
    col:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -TOPBAR_H / 2)  -- re-pointed by ApplyLayout
    col:RegisterForClicks("AnyDown")
    SkinButtonChrome(col)
    local colFs = TrackFont(f, EllesmereUI.MakeFont(col, 16, nil, 1, 1, 1), 16)
    colFs:SetPoint("CENTER", col, "CENTER", 0, 1)
    colFs:SetText("-")
    colFs:SetAlpha(0.7)
    col:SetScript("OnEnter", function(self)
        colFs:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(EllesmereUI.L("Minimize"))
        GameTooltip:Show()
    end)
    col:SetScript("OnLeave", function()
        colFs:SetAlpha(0.7)
        GameTooltip:Hide()
    end)
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

    local function PackRows(buttons, perRow)
        local rows, row = {}, {}
        perRow = perRow or 2
        for _, b in ipairs(buttons) do
            if b then
                row[#row + 1] = b
                if #row == perRow then rows[#rows + 1] = row; row = {} end
            end
        end
        if #row > 0 then rows[#rows + 1] = row end
        return rows
    end

    -- Pings and Difficulty sit directly between Make Everyone Assistant and
    -- the ordinary action block. Every optional survivor compacts leftward.
    local pre = {}
    if ButtonShown("showPings") and C_PartyInfo.GetRestrictPings and C_PartyInfo.SetRestrictPings then
        pre[#pre + 1] = runtime.pingButton
    end
    if ButtonShown("showDifficulty") then pre[#pre + 1] = runtime.difficultyButton end
    local preRows = PackRows(pre, 2)

    local actions = { readyButton }
    if ButtonShown("showRoleCheck") then actions[#actions + 1] = roleButton end
    if ButtonShown("showConvert")   then actions[#actions + 1] = convertButton end
    if ButtonShown("showDisband")   then actions[#actions + 1] = disbandButton end
    local actionRows = PackRows(actions, 2)

    -- Keep the existing Pull/Stop row exactly as it was. Break is the next
    -- control after Stop: when that row currently has fewer than three buttons
    -- it fills the next slot; once the Stop row already has three (or more)
    -- controls, Break gets the immediately adjacent row by itself.
    local timerRows = {}
    local pullRow
    local times = VisiblePullTimes()
    if #times > 0 then
        pullRow = {}
        for i, secs in ipairs(times) do
            local b = pullButtons[i]
            b.secs = secs
            b._lbl:SetText(tostring(secs))
            pullRow[#pullRow + 1] = b
        end
        pullRow[#pullRow + 1] = stopButton
        timerRows[#timerRows + 1] = pullRow
    end

    local breakSecs = runtime.BreakTime()
    if breakSecs > 0 then
        runtime.breakButton.secs = breakSecs
        runtime.breakButton._lbl:SetText(runtime.BreakLabel(breakSecs))
        if pullRow and #pullRow < 3 then
            pullRow[#pullRow + 1] = runtime.breakButton
        else
            timerRows[#timerRows + 1] = { runtime.breakButton }
        end
    end

    for _, b in ipairs(groupButtons) do b:Hide() end

    local fullW = PANEL_W - PAD * 2
    local function PlaceRow(row, y)
        if not row or #row == 0 then return end
        local n = #row
        local w = (fullW - ROW_GAP * (n - 1)) / n
        for i, b in ipairs(row) do
            b:SetWidth(w)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (w + ROW_GAP) * (i - 1), y)
            b:Show()
        end
    end

    local hasReports = #reportBtns > 0
    local isUp = AnchorCorner():find("BOTTOM") ~= nil
    local blocks = {}
    local function Push(kind, payload, h)
        blocks[#blocks + 1] = { kind = kind, payload = payload, h = h }
    end
    local function PushRows(rows, reverse)
        if reverse then
            for i = #rows, 1, -1 do Push("row", rows[i], ROW_H) end
        else
            for _, row in ipairs(rows) do Push("row", row, ROW_H) end
        end
    end

    -- Restore the pre-feature Raid Tools stack and insert the new controls at
    -- the requested boundaries. With Grow Direction = UP, physical top->bottom
    -- is: Assistant -> Pings/Difficulty -> actions -> Pull/Stop -> Break ->
    -- Roles -> Target -> World -> Raid Groups -> reports. DOWN is its vertical
    -- mirror. Roles lives in the markers holder, at the edge touching Break.
    if isUp then
        Push("assist", nil, ROW_H)
        PushRows(preRows, true)
        PushRows(actionRows, true)
        PushRows(timerRows, false)
        if ShowAs() == "one" and MARKERS_CONTENT_H then Push("markers", nil, MARKERS_CONTENT_H) end
        if hasReports then Push("row", reportBtns, ROW_H) end
    else
        if hasReports then Push("row", reportBtns, ROW_H) end
        if ShowAs() == "one" and MARKERS_CONTENT_H then Push("markers", nil, MARKERS_CONTENT_H) end
        PushRows(timerRows, true)
        PushRows(actionRows, false)
        PushRows(preRows, false)
        Push("assist", nil, ROW_H)
    end

    local y = 0
    COMBINED_MARKERS_TOP = 0
    for i, block in ipairs(blocks) do
        if block.kind == "row" then
            PlaceRow(block.payload, y)
        elseif block.kind == "assist" then
            assistCheckRow:ClearAllPoints()
            assistCheckRow:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
            assistCheckRow:Show()
        elseif block.kind == "markers" then
            COMBINED_MARKERS_TOP = -y
        end

        y = y - block.h
        if i < #blocks then
            local nextBlock = blocks[i + 1]
            local aroundMarkers = block.kind == "markers" or nextBlock.kind == "markers"
            y = y - (aroundMarkers and ROW_GAP * 2 or ROW_GAP)
        end
    end

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

    -- Make Everyone Assistant is a fixed full-width row whose edge position
    -- follows Grow Direction (LayoutGroupContent positions it). Whole-row button (not
    -- just the box) so the label is as clickable as the tick -- same
    -- reasoning as the pull/marker rows' generous hit targets.
    assistCheckRow = CreateFrame("Button", nil, f)
    assistCheckRow:SetSize(PANEL_W - PAD * 2, ROW_H)
    assistCheckRow:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, 0) -- re-pointed by LayoutGroupContent
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
        local desired = not AllAssistants()
        if SetEveryoneAssistant(desired) then
            -- Show the requested state immediately; roster events below
            -- reconcile it with the authoritative server state as promotions
            -- or demotions arrive. Re-reading the roster synchronously here
            -- used to restore the old state before the server had answered.
            assistCheckTex:SetShown(desired)
        end
    end)
    -- Leader controls are created first because their layout block sits before
    -- Ready Check. They remain visible-but-grey to non-leaders rather than
    -- disappearing, so the panel does not jump around as leadership changes.
    runtime.pingButton = MakeGroupButton(f, "Pings", full, function(self) runtime.ShowPingMenu(self) end, true)
    runtime.difficultyButton = MakeGroupButton(f, "Difficulty", full,
        function(self) runtime.ShowDifficultyMenu(self) end, true)

    -- MakeGroupButton runs labels through L itself. Action buttons are born
    -- unplaced at full-row width; LayoutGroupContent re-flows the survivors.
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

    local b
    b = MakeGroupButton(f, "Break", full, function() runtime.StartBreak(b.secs) end)
    runtime.breakButton = b
    runtime.RefreshDifficultyLabel()

    -- A height right away: BuildAll has callers (the slash command, unlock
    -- mode) that reach the shells without going through Apply.
    LayoutGroupContent()
end

-- Marker rows mirror with the combined window. In UP, Roles is the first
-- marker row so it sits directly below Break, followed by Target / World /
-- Raid Groups. DOWN reverses that stack, leaving Roles at the bottom edge next
-- to Break. Party/solo layouts omit Roles.
local MARKER_ROWS = {
    { kind = "target", label = "Target Markers" },
    { kind = "world",  label = "World Markers"  },
}

local function LayoutMarkersContent()
    if not markersHolder or not raidGroupsRowLabel then return end
    local f = markersHolder
    local isUp = AnchorCorner():find("BOTTOM") ~= nil
    local roles = runtime.RolesShown()
    local order
    if isUp then
        order = roles and { "roles", "target", "world", "groups" }
                      or { "target", "world", "groups" }
    else
        order = roles and { "groups", "world", "target", "roles" }
                      or { "groups", "world", "target" }
    end
    local y = 0
    local step = (PANEL_W - PAD * 2 - MARKER_SZ) / 8

    if runtime.roleCountRowLabel then runtime.roleCountRowLabel:SetShown(roles) end
    for _, b in ipairs(runtime.roleCountButtons) do b:SetShown(roles) end

    local function PlaceMarkerRow(kind)
        local lbl = markerRowLabels[kind]
        lbl:ClearAllPoints()
        lbl:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
        y = y - MARKER_LBL_H - 2
        for i, b in ipairs(markerRowButtons[kind]) do
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + step * (i - 1), y)
        end
        y = y - MARKER_SZ
    end

    local function PlaceRolesRow()
        runtime.roleCountRowLabel:ClearAllPoints()
        runtime.roleCountRowLabel:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
        y = y - MARKER_LBL_H - 2
        local n = #runtime.roleColumns
        local w = (PANEL_W - PAD * 2 - (n - 1) * ROW_GAP) / n
        for i, b in ipairs(runtime.roleCountButtons) do
            b:SetWidth(w)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (w + ROW_GAP) * (i - 1), y)
        end
        y = y - ROW_H
    end

    local function PlaceGroupsRow()
        raidGroupsRowLabel:ClearAllPoints()
        raidGroupsRowLabel:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
        y = y - MARKER_LBL_H - 2
        local gw = (PANEL_W - PAD * 2 - (RAID_GROUPS - 1) * ROW_GAP) / RAID_GROUPS
        for i, gb in ipairs(raidGroupButtons) do
            gb:SetWidth(gw)
            gb:ClearAllPoints()
            gb:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (gw + ROW_GAP) * (i - 1), y)
        end
        y = y - ROW_H
    end

    for i, kind in ipairs(order) do
        if kind == "groups" then
            PlaceGroupsRow()
        elseif kind == "roles" then
            PlaceRolesRow()
        else
            PlaceMarkerRow(kind)
        end
        if i < #order then y = y - ROW_GAP * 2 end
    end

    MARKERS_CONTENT_H = -y
    f:SetHeight(MARKERS_CONTENT_H)
end

local function BuildMarkersContent()
    markersHolder = CreateFrame("Frame", nil, sections.Markers)
    markersHolder:SetWidth(PANEL_W)
    fontOwners[#fontOwners + 1] = markersHolder
    local f = markersHolder

    -- Secure marker buttons are built once; only their anchors move later.
    for _, row in ipairs(MARKER_ROWS) do
        local lbl = TrackFont(f, EllesmereUI.MakeFont(f, 9, nil, 1, 1, 1), 9)
        lbl:SetAlpha(0.55)
        lbl:SetText(EllesmereUI.L(row.label))
        markerRowLabels[row.kind] = lbl
        for i = 0, 8 do
            MakeMarkerButton(f, i == 8 and 0 or (i + 1), row.kind)
        end
    end

    runtime.roleCountRowLabel = TrackFont(f, EllesmereUI.MakeFont(f, 9, nil, 1, 1, 1), 9)
    runtime.roleCountRowLabel:SetAlpha(0.55)
    runtime.roleCountRowLabel:SetText(EllesmereUI.L("Roles"))
    local roleW = (PANEL_W - PAD * 2 - (#runtime.roleColumns - 1) * ROW_GAP) / #runtime.roleColumns
    for _, def in ipairs(runtime.roleColumns) do
        local b = MakeGroupButton(f, "", roleW, nil, nil, runtime.roleCountButtons)
        b:EnableMouse(false)
        b._lbl:SetText(EllesmereUI.L(def.label) .. " 0")
    end

    raidGroupsRowLabel = TrackFont(f, EllesmereUI.MakeFont(f, 9, nil, 1, 1, 1), 9)
    raidGroupsRowLabel:SetAlpha(0.55)
    raidGroupsRowLabel:SetText(EllesmereUI.L(RAIDGROUPS_ROW_LABEL))

    local gw = (PANEL_W - PAD * 2 - (RAID_GROUPS - 1) * ROW_GAP) / RAID_GROUPS
    for i = 1, RAID_GROUPS do MakeRaidGroupButton(f, i, gw) end

    LayoutMarkersContent()
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
-- Same chrome and size as the shell's own close button (22x22, SkinButtonChrome,
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
    local lbl = TrackFont(sections.Group, EllesmereUI.MakeFont(b, 18, nil, 1, 1, 1), 18)
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
    local lbl = TrackFont(sections.Group, EllesmereUI.MakeFont(b, 16, nil, 1, 1, 1), 16)
    lbl:SetPoint("CENTER", b, "CENTER", 0, -2)
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

-- Embedded Invite Tools launcher. The supplied .blp is intentionally used
-- only here; the Invite Tools window itself follows EUI's normal chrome.
local function BuildInviteToolsButton()
    local b = CreateFrame("Button", nil, sections.Group)
    b:SetSize(COG_SZ, COG_SZ)
    b:SetFrameLevel(sections.Group:GetFrameLevel() + 5)
    SkinButtonChrome(b)

    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetSize(14, 14)
    tex:SetPoint("CENTER")
    tex:SetTexture("Interface\\AddOns\\EllesmereUIQoL\\Media\\InviteTools.blp")
    tex:SetAlpha(0.7)

    b:SetScript("OnEnter", function(self)
        tex:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(EllesmereUI.L("Invite Tools"))
        GameTooltip:AddLine(EllesmereUI.L("Opens Invite Tools for managing and sharing invite lists."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        tex:SetAlpha(0.7)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function()
        if ns.ToggleInviteTools then ns.ToggleInviteTools() end
    end)

    b._icon = tex
    inviteToolsBtn = b
end

-- Flask/Food/Repair/Rune/Vantus report buttons: left-click prints who is
-- missing it (or, for Repair, everyone's durability percentage) to this
-- client's own chat frame only; right-click posts the same thing to /guild
-- (in a raid) or /party (in a party) depending on the current group.
-- Middle-click always posts to that same guild/party chat: on every button
-- except Food, it fires all five reports at once (ns.ReportAllConsumables);
-- on Food specifically, it reports who is missing a food buff whose name
-- starts with "Hearty" instead of the ordinary Well Fed check
-- (ns.ReportHeartyFood) -- both defined in EllesmereUIQoL_RaidCheck.lua.
-- Full-row content buttons, deliberately separate from the corner chrome.
-- They use the same 22px row height and equal-width distribution as the rest
-- of Group & Pull. Not gated on lead/assist -- reading auras and durability
-- someone volunteered is not an action that needs rank -- and, unlike
-- Convert/Disband, NOT greyed out during a boss pull either: reporting a
-- status line mid-fight carries no game-state risk, so these stay clickable
-- through combat and encounters (see RefreshReportButtons).
local function BuildReportButtons()
    for _, def in ipairs(REPORT_COLUMNS) do
        local b = CreateFrame("Button", nil, groupHolder)
        b:SetHeight(ROW_H)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
        SkinButtonChrome(b)
        local lbl = TrackFont(groupHolder, EllesmereUI.MakeFont(b, 11, nil, 1, 1, 1), 11)
        lbl:SetPoint("CENTER", b, "CENTER", 0, 0)
        lbl:SetText(EllesmereUI.L(def.title))
        lbl:SetAlpha(0.7)
        -- Width is assigned by LayoutGroupContent so all five buttons fill
        -- exactly one panel row with the same spacing as the action rows.
        b:SetScript("OnEnter", function(self)
            lbl:SetAlpha(1)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(EllesmereUI.L(def.title))
            if def.key == "durability" then
                GameTooltip:AddLine(EllesmereUI.L("Lists anyone at 90% or below, worst first."), 0.7, 0.7, 0.7, true)
            else
                GameTooltip:AddLine(EllesmereUI.L("Lists who is missing it."), 0.7, 0.7, 0.7, true)
            end
            GameTooltip:AddLine(EllesmereUI.L("Left Click: print to your own chat only."), 1, 1, 1)
            GameTooltip:AddLine(EllesmereUI.L("Right Click: report to party/guild chat."), 1, 1, 1)
            if def.key == "food" then
                GameTooltip:AddLine(EllesmereUI.L("Middle Click: report who is missing a \"Hearty\" food, to party/guild chat."), 1, 1, 1)
            else
                GameTooltip:AddLine(EllesmereUI.L("Middle Click: report every consumable check at once, to party/guild chat."), 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            lbl:SetAlpha(0.7)
            GameTooltip:Hide()
        end)
        b:SetScript("OnClick", function(_, button)
            if button == "MiddleButton" then
                if def.key == "food" then
                    if ns.ReportHeartyFood then ns.ReportHeartyFood(true) end
                elseif ns.ReportAllConsumables then
                    ns.ReportAllConsumables(true)
                end
                return
            end
            if ns.ReportConsumable then
                ns.ReportConsumable(def.key, button == "RightButton")
            end
        end)
        b._lbl = lbl
        reportBtns[#reportBtns + 1] = b
    end
    LayoutGroupContent()
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
    BuildInviteToolsButton()
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
-- Groups cog, Raid Check button and Invite Tools button all share this same corner. Reports
-- are content-row buttons and do not participate in corner placement.

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
    local corner = AnchorCorner()
    local isBottom = corner == "BOTTOMLEFT" or corner == "BOTTOMRIGHT"
    -- In the combined shell the title now shares the corner-control row, on
    -- the opposite horizontal edge. Down-left/down-right carry that row on
    -- TOP, so content starts after the 22px controls plus an 8px gap. Up-left/
    -- up-right carry it on BOTTOM, so the content can still start at PAD and
    -- the old empty title-band space does not come back. Split mode keeps its
    -- ordinary top title when controls live on the bottom edge.
    local groupContentTop
    if showAs == "one" then
        groupContentTop = isBottom and PAD or GROUP_TOP_RESERVE
    else
        groupContentTop = isBottom and CONTENT_TOP or GROUP_TOP_RESERVE
    end
    local function Reserve(hasBtn, extra)
        local titleReserve  = (hasBtn and corner == "TOPLEFT")
            and (BTN_TITLE_RESERVE + (extra or 0)) or PAD
        local bottomReserve = (hasBtn and isBottom) and BTN_BOTTOM_RESERVE or 0
        return titleReserve, bottomReserve
    end
    -- Raid Groups / Raid Check exist independently of the collapse toggle,
    -- and keep the collapse slot reserved even when Minimize itself is hidden.
    -- That prevents the larger bottom-corner controls from ever landing over
    -- the last content row and keeps split-mode titles clear of them as well.
    local groupHasCornerControls = collapseUI or raidGroupsCogBtn ~= nil or raidCheckBtn ~= nil or inviteToolsBtn ~= nil
    local groupTitleReserve, groupBottomReserve = Reserve(groupHasCornerControls, GROUP_COG_RESERVE)
    local markersTitleReserve, markersBottomReserve = Reserve(markersHasBtn)

    if showAs == "one" then
        -- Combined mode keeps a compact Raid Tools title in the unused side
        -- of the same edge that carries Minimize / Raid Groups / Raid Check / Invite Tools.
        -- Its exact anchor is assigned below after the shell is sized.
        shellTitle.Group:SetShown(true)
        shellTitle.Group:SetText(EllesmereUI.L(COMBINED_LABEL))
        SetTrackedFontSize(shellTitleFont.Group, 14)
        groupHolder:SetShown(true)
        groupHolder:SetParent(winGroup)
        groupHolder:ClearAllPoints()
        groupHolder:SetPoint("TOPLEFT", winGroup, "TOPLEFT", 0, -groupContentTop)
        markersHolder:SetShown(true)
        markersHolder:SetParent(winGroup)
        markersHolder:ClearAllPoints()
        markersHolder:SetPoint("TOPLEFT", winGroup, "TOPLEFT", 0,
            -groupContentTop - COMBINED_MARKERS_TOP)
        winGroup:SetHeight(groupContentTop + GROUP_CONTENT_H + PAD + groupBottomReserve)
    else
        -- Every split mode parents each holder to its own shell; which shells
        -- actually SHOW is ApplyVisibility's call (the enabled attribute).
        shellTitle.Group:SetShown(true)
        shellTitle.Group:SetText(EllesmereUI.L(SECTION_LABEL.Group))
        SetTrackedFontSize(shellTitleFont.Group, 12)
        groupHolder:SetParent(winGroup)
        groupHolder:SetShown(true)
        groupHolder:ClearAllPoints()
        groupHolder:SetPoint("TOPLEFT", winGroup, "TOPLEFT", 0, -groupContentTop)
        winGroup:SetHeight(groupContentTop + GROUP_CONTENT_H + PAD + groupBottomReserve)

        markersHolder:SetParent(winMarkers)
        markersHolder:SetShown(true)
        markersHolder:ClearAllPoints()
        markersHolder:SetPoint("TOPLEFT", winMarkers, "TOPLEFT", 0, -CONTENT_TOP)
        winMarkers:SetHeight(CONTENT_TOP + MARKERS_CONTENT_H + PAD + markersBottomReserve)
    end

    -- Group title: in combined mode it occupies the free side opposite the
    -- corner controls and follows them to TOP/BOTTOM with Grow Direction. In
    -- split mode it keeps the normal top-left title placement and reserve.
    shellTitle.Group:ClearAllPoints()
    if showAs == "one" then
        local controlsOnLeft = corner:find("LEFT") ~= nil
        if isBottom then
            local y = BTN_MARGIN + CORNER_BTN_SZ / 2
            if controlsOnLeft then
                shellTitle.Group:SetPoint("RIGHT", winGroup, "BOTTOMRIGHT", -PAD, y)
                shellTitle.Group:SetJustifyH("RIGHT")
            else
                shellTitle.Group:SetPoint("LEFT", winGroup, "BOTTOMLEFT", PAD, y)
                shellTitle.Group:SetJustifyH("LEFT")
            end
        else
            local y = -(BTN_MARGIN + CORNER_BTN_SZ / 2)
            if controlsOnLeft then
                shellTitle.Group:SetPoint("RIGHT", winGroup, "TOPRIGHT", -PAD, y)
                shellTitle.Group:SetJustifyH("RIGHT")
            else
                shellTitle.Group:SetPoint("LEFT", winGroup, "TOPLEFT", PAD, y)
                shellTitle.Group:SetJustifyH("LEFT")
            end
        end
    else
        shellTitle.Group:SetPoint("LEFT", winGroup, "TOPLEFT", groupTitleReserve, -TOPBAR_H / 2)
        shellTitle.Group:SetJustifyH("LEFT")
    end
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
        local inward = COG_GAP + CORNER_BTN_SZ
        local cogDx = off[1] + (isLeftCorner and inward or -inward)
        raidGroupsCogBtn:ClearAllPoints()
        raidGroupsCogBtn:SetPoint(corner, winGroup, corner, cogDx, off[2])
    end

    -- Raid Check button: same corner, one further gap inward past the cog.
    if raidCheckBtn then
        local isLeftCorner = corner:find("LEFT") ~= nil
        local inward = (COG_GAP + CORNER_BTN_SZ) + (RAIDCHECK_GAP + COG_SZ)
        local rcDx = off[1] + (isLeftCorner and inward or -inward)
        raidCheckBtn:ClearAllPoints()
        raidCheckBtn:SetPoint(corner, winGroup, corner, rcDx, off[2])
    end

    -- Invite Tools sits directly beyond Raid Check in the grow direction:
    -- right of '*' for right-growing menus, left of '*' for left-growing ones.
    if inviteToolsBtn then
        local isLeftCorner = corner:find("LEFT") ~= nil
        local inward = (COG_GAP + CORNER_BTN_SZ) + (RAIDCHECK_GAP + COG_SZ)
                    + (INVITETOOLS_GAP + COG_SZ)
        local itDx = off[1] + (isLeftCorner and inward or -inward)
        inviteToolsBtn:ClearAllPoints()
        inviteToolsBtn:SetPoint(corner, winGroup, corner, itDx, off[2])
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
        local iconFaded = (ButtonVisibility() == "mouseover") and not previewOn
        iconBtn:SetAlpha((not iconFaded or iconBtn:IsMouseOver()) and 1 or 0)
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
        if not sections.Group or previewOn
           or (Visibility() ~= "mouseover" and ButtonVisibility() ~= "mouseover") then return end
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

-- Build the first-free run from live marker state. Protected attributes cannot
-- be changed during combat, so the secure Place button consumes the last run
-- prepared out of combat and PLAYER_REGEN_ENABLED refreshes it afterward.
--
-- IsRaidMarkerActive answers a SECRET boolean during chat messaging lockdown:
-- on every dungeon and raid map, in or out of combat, and through boss
-- encounters, keystones and PvP matches. A secret cannot choose which
-- attributes to write; no snippet can read marker state, and the one secure
-- action that tests it (the worldmarker toggle) flips a single fixed marker,
-- so it cannot pick the first free one. While the answer is secret the run
-- already prepared is kept, and Place, Undo and Clear carry on by position
-- exactly as they do in combat. A full Star to Skull run starts instead when
-- the instance changed (runtime.qfZonedPending, latched at PLAYER_ENTERING_WORLD
-- so a zone-in during combat still lands here), when no run exists yet, or
-- when the run is used up -- clears are invisible while secret (ours, /cwm,
-- another player's), so an exhausted run starts over rather than going dead.
-- Markers already on the ground are not skipped then. The answers are all
-- read before anything is written, so a secret never leaves a half-built run.
-- An instance change also empties the Undo stack: its markers are gone.
local function PrimeQuickFire(place)
    if not place or InCombatLockdown() then return end
    local zoned = runtime.qfZonedPending
    local free = runtime.qfFree
    if not free then free = {}; runtime.qfFree = free end
    for i = 1, 8 do
        local active = IsRaidMarkerActive and IsRaidMarkerActive(SYMBOL_TO_WORLD[i])
        if issecretvalue(active) then
            local n = tonumber(place:GetAttribute("qfAvailCount"))
            if zoned or not n or (tonumber(place:GetAttribute("qfAvailPos")) or 0) >= n then
                for j = 1, 8 do place:SetAttribute("qfAvail" .. j, j) end
                place:SetAttribute("qfAvailCount", 8)
                place:SetAttribute("qfAvailPos", 0)
                if zoned or not n then place:SetAttribute("qfDepth", 0) end
                runtime.qfZonedPending = nil
            end
            return
        end
        free[i] = not active
    end
    local count = 0
    for i = 1, 8 do
        if free[i] then
            count = count + 1
            place:SetAttribute("qfAvail" .. count, i)
        end
    end
    for i = count + 1, 8 do place:SetAttribute("qfAvail" .. i, nil) end
    place:SetAttribute("qfAvailCount", count)
    place:SetAttribute("qfAvailPos", 0)
    if zoned then place:SetAttribute("qfDepth", 0) end
    runtime.qfZonedPending = nil
end

-- The three invisible buttons are created only after Quick Fire is enabled.
-- Their secure click snippets keep Place, Undo and Clear usable in combat;
-- changing the bindings themselves still follows WoW's normal combat lock.
local function BuildQuickFire()
    if runtime.qfPlace then return end

    runtime.qfHeader = CreateFrame("Frame", "EllesmereUIRaidToolsQuickFireHeader",
        UIParent, "SecureHandlerBaseTemplate")

    local place = CreateFrame("Button", "EllesmereUIRaidToolsQuickFirePlace",
        UIParent, "SecureActionButtonTemplate")
    place:RegisterForClicks("AnyDown")
    place:SetAttribute("useOnKeyDown", true)
    place:EnableMouse(false)
    place:SetSize(1, 1)
    place:SetAlpha(0)
    place:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -120, -120)
    place:Show()
    place:SetAttribute("qfCount", 8)
    place:SetAttribute("qfDepth", 0)
    for i = 1, 8 do
        place:SetAttribute("qfMarker" .. i, SYMBOL_TO_WORLD[i])
        place:SetAttribute("qfPlaceMacro" .. i,
            (SLASH_WORLD_MARKER1 or "/wm") .. " [@cursor] " .. SYMBOL_TO_WORLD[i])
    end
    place:SetScript("PreClick", function(self) PrimeQuickFire(self) end)
    SecureHandlerWrapScript(place, "OnClick", runtime.qfHeader, [[
        self:SetAttribute("type", nil)
        self:SetAttribute("macrotext", nil)
        local n = tonumber(self:GetAttribute("qfCount")) or 8
        local available = tonumber(self:GetAttribute("qfAvailCount")) or 0
        local nextPos = (tonumber(self:GetAttribute("qfAvailPos")) or 0) + 1
        if nextPos > available then return end
        local pos = tonumber(self:GetAttribute("qfAvail" .. nextPos))
        if not pos then return end
        self:SetAttribute("qfAvailPos", nextPos)

        local depth = tonumber(self:GetAttribute("qfDepth")) or 0
        if depth >= n then
            for i = 1, n - 1 do
                self:SetAttribute("qfStack" .. i,
                    self:GetAttribute("qfStack" .. (i + 1)))
            end
            depth = n - 1
        end
        depth = depth + 1
        self:SetAttribute("qfDepth", depth)
        self:SetAttribute("qfStack" .. depth, pos)
        self:SetAttribute("macrotext", self:GetAttribute("qfPlaceMacro" .. pos))
        self:SetAttribute("type", "macro")
    ]], [[
        self:SetAttribute("type", nil)
        self:SetAttribute("macrotext", nil)
    ]])

    local undo = CreateFrame("Button", "EllesmereUIRaidToolsQuickFireUndo",
        UIParent, "SecureActionButtonTemplate")
    undo:RegisterForClicks("AnyDown")
    undo:SetAttribute("useOnKeyDown", true)
    undo:EnableMouse(false)
    undo:SetSize(1, 1)
    undo:SetAlpha(0)
    undo:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -124, -120)
    undo:Show()
    SecureHandlerSetFrameRef(undo, "place", place)
    SecureHandlerWrapScript(undo, "OnClick", runtime.qfHeader, [[
        self:SetAttribute("type", nil)
        self:SetAttribute("action", nil)
        self:SetAttribute("marker", nil)
        local place = self:GetFrameRef("place")
        local depth = place and (tonumber(place:GetAttribute("qfDepth")) or 0) or 0
        if depth < 1 then return end
        local pos = tonumber(place:GetAttribute("qfStack" .. depth))
        if not pos then return end
        place:SetAttribute("qfStack" .. depth, nil)
        place:SetAttribute("qfDepth", depth - 1)
        local availablePos = tonumber(place:GetAttribute("qfAvailPos")) or 0
        if availablePos > 0
           and tonumber(place:GetAttribute("qfAvail" .. availablePos)) == pos then
            place:SetAttribute("qfAvailPos", availablePos - 1)
        end
        self:SetAttribute("marker", place:GetAttribute("qfMarker" .. pos))
        self:SetAttribute("action", "clear")
        self:SetAttribute("type", "worldmarker")
    ]], [[
        self:SetAttribute("type", nil)
        self:SetAttribute("action", nil)
        self:SetAttribute("marker", nil)
    ]])

    local clear = CreateFrame("Button", "EllesmereUIRaidToolsQuickFireClear",
        UIParent, "SecureActionButtonTemplate")
    clear:RegisterForClicks("AnyDown")
    clear:SetAttribute("useOnKeyDown", true)
    clear:EnableMouse(false)
    clear:SetSize(1, 1)
    clear:SetAlpha(0)
    clear:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -128, -120)
    clear:Show()
    SecureHandlerSetFrameRef(clear, "place", place)
    SecureHandlerWrapScript(clear, "OnClick", runtime.qfHeader, [[
        local place = self:GetFrameRef("place")
        if place then
            local n = tonumber(place:GetAttribute("qfCount")) or 8
            place:SetAttribute("qfDepth", 0)
            place:SetAttribute("qfAvailCount", n)
            place:SetAttribute("qfAvailPos", 0)
            for i = 1, n do
                place:SetAttribute("qfAvail" .. i, i)
                place:SetAttribute("qfStack" .. i, nil)
            end
        end
        self:SetAttribute("macrotext", self:GetAttribute("qfClearMacro"))
        self:SetAttribute("type", "macro")
    ]], [[
        self:SetAttribute("type", nil)
        self:SetAttribute("macrotext", nil)
    ]])
    clear:SetAttribute("qfClearMacro",
        (SLASH_CLEAR_WORLD_MARKER1 or "/cwm") .. " " .. (ALL or "All"))

    runtime.qfPlace, runtime.qfUndo, runtime.qfClear = place, undo, clear
    runtime.qfBindingOwner = CreateFrame("Frame")
    PrimeQuickFire(place)
end

local function ApplyQuickFireBindings()
    local p = P()
    if runtime.qfBindingOwner then ClearOverrideBindings(runtime.qfBindingOwner) end
    if not p or p.quickFire ~= true or Mode() == "never" or AssistSuppressed() then return end

    BuildQuickFire()
    PrimeQuickFire(runtime.qfPlace)
    local bindings = {
        { p.quickFirePlaceKey, "EllesmereUIRaidToolsQuickFirePlace" },
        { p.quickFireUndoKey,  "EllesmereUIRaidToolsQuickFireUndo" },
        { p.quickFireClearKey, "EllesmereUIRaidToolsQuickFireClear" },
    }
    for _, binding in ipairs(bindings) do
        if binding[1] and binding[1] ~= "" then
            SetOverrideBindingClick(runtime.qfBindingOwner, false, binding[1], binding[2])
        end
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
            -- Quick Fire shares these events, but each only does work while
            -- enabled. An old Quick Fire frame can survive being disabled. An
            -- instance change is latched for the next prime out of combat (see
            -- PrimeQuickFire); a loading screen inside the same instance is not one.
            if event == "PLAYER_ENTERING_WORLD" then
                local zone = select(8, GetInstanceInfo())
                if zone ~= runtime.qfZone then
                    runtime.qfZone = zone
                    runtime.qfZonedPending = true
                end
            end
            if event == "RAID_TARGET_UPDATE" or event == "PLAYER_REGEN_ENABLED"
               or event == "PLAYER_ENTERING_WORLD" then
                local p = P()
                if p and p.quickFire == true and runtime.qfPlace then
                    PrimeQuickFire(runtime.qfPlace)
                end
            end
            local roleLayoutChanged = runtime.RefreshRoleCounts()
            if roleLayoutChanged then
                Apply()
                return
            end
            RefreshPermissions()
            -- Permission inputs are memoized, but these stateful controls can
            -- change while leader/assist/group type stays identical. Always
            -- refresh them from their authoritative APIs on the registered
            -- roster/roles/difficulty events instead of hiding that update
            -- behind RefreshPermissions' early-return cache.
            RefreshAssistCheckbox()
            runtime.RefreshDifficultyLabel()
            RefreshRaidGroups()
            RefreshAssistGate()
            RefreshReportButtons()
        end)
    end
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("PARTY_LEADER_CHANGED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    ev:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("ENCOUNTER_START")
    ev:RegisterEvent("ENCOUNTER_END")
    local p = P()
    if Mode() ~= "never" and (p and p.quickFire == true) then
        ev:RegisterEvent("RAID_TARGET_UPDATE")
    else
        ev:UnregisterEvent("RAID_TARGET_UPDATE")
    end
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
        if runtime.qfBindingOwner then ClearOverrideBindings(runtime.qfBindingOwner) end
        -- Fully off and nothing pending: no reason to keep hearing roster
        -- spam. Never-activated sessions never created the frame at all.
        DropEvents()
        return
    end

    EnsureEvents()
    RegisterUnlock()
    BuildAll()
    -- Before ApplyLayout: marker order follows Grow Direction, then Group
    -- layout reserves that marker block at the exact point in the combined
    -- stack while also sizing around hidden buttons / 0-second pull slots.
    LayoutMarkersContent()
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
    ApplyQuickFireBindings()
    ApplyFonts()
    RefreshPermissions(true)
    runtime.RefreshRoleCounts(true)
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
