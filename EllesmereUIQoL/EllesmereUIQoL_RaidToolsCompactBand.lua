if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_RaidToolsCompactBand.lua -- standalone Compact Band
--
--  A copy of the 9.0.7 "Compact Band" Raid Tools layout (8 markers + Clear +
--  Ready/Role Check + Pull Timer in one resizable row), pulled OUT of the
--  Raid Tools "Show as" switch and turned into its own independent window:
--
--    * Its own Enable switch -- it can run at the same time as ANY Raid
--      Tools "Show as" layout (One Window, Two Windows, Only Group & Pull,
--      Only Markers), or with Raid Tools fully disabled ("Never").
--    * Its own Always / Mouseover display option, set from the options page.
--    * Its own saved position, size and background color/opacity,
--      independent of Raid Tools' windows.
--
--  The shell keeps the SAME flat black overlay the 9.0.7 Compact Band draws
--  behind its buttons (Raid Tools' ApplyShellMaterial hides the art/title/
--  border in compact mode but never hides that overlay) -- color and
--  opacity are exposed on the options page instead of hardcoded.
--
--  It still reads the Show Role Check switch from the Raid Tools module
--  (through the _EUI_RaidTools_DB global that module publishes), so "RC" on
--  the band always matches the main panel's own setting. The Pull Timer
--  ("PT") is fully independent instead: fixed Left Click / Shift + Left
--  Click durations (see PULL_BAND_FIRST/SECOND below), not tied to Raid
--  Tools' three-slot Pull Timer config. Everything else (frame, buttons,
--  tooltip, position, visibility) is fully independent and
--  this file works fine even if EllesmereUIQoL_RaidTools.lua's own panel is
--  set to "Never".
--
--  COMBAT MODEL: the shell is a PLAIN frame (no Secure*Template), so
--  Show/Hide/SetScale/SetSize on it are never combat-restricted. Only the
--  marker buttons are secure (SecureActionButtonTemplate); they are built
--  once and never re-parented, resized or individually shown/hidden -- only
--  the plain shell around them is. Moving/resizing only happens through
--  Unlock Mode, which already refuses to open in combat (see /unlock).
-------------------------------------------------------------------------------
local _, ns = ...

local InCombatLockdown = InCombatLockdown
local UnitIsGroupLeader, UnitIsGroupAssistant = UnitIsGroupLeader, UnitIsGroupAssistant
local IsInRaid, IsInGroup = IsInRaid, IsInGroup
local SetRaidTargetIconTexture = SetRaidTargetIconTexture

-------------------------------------------------------------------------------
--  Layout constants -- match the 9.0.7 Compact Band geometry exactly so the
--  band looks identical to the one in that version.
-------------------------------------------------------------------------------
local CB_H              = 40
local CB_W               = 400
local CB_MIN_W           = 365
local CB_MIN_H           = 28
local CB_PAD             = 6
local CB_ICON            = 28
local CB_GAP             = 4
local CB_DIVIDER_OFFSET  = 5

local MARKER_SHEET = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
-- Sheet SYMBOL order (1 Star .. 8 Skull) mapped to WORLD marker id order
-- (1 Blue .. 8 White) -- see EllesmereUIQoL_RaidTools.lua for the full note.
local SYMBOL_TO_WORLD = { 5, 6, 3, 2, 7, 1, 4, 8 }
local MARKER_NAME = {
    "Star", "Circle", "Diamond", "Triangle",
    "Moon", "Square", "Cross", "Skull",
}
local MARKER_TIP_ROWS = {
    { "Left Click",          "Toggle target marker" },
    { "Right Click",         "Place world marker" },
    { "Shift + Left Click",  "Clear target marker" },
    { "Shift + Right Click", "Clear world marker" },
}
local CLEAR_TIP_ROWS = {
    { "Left Click",  "Clear target marker" },
    { "Right Click", "Clear all world markers" },
}

-------------------------------------------------------------------------------
--  Saved variables -- own slice of the shared QoL profile, same arrangement
--  every QoL feature uses (each merges its own defaults into the same table).
-------------------------------------------------------------------------------
local DB_DEFAULTS = {
    profile = {
        raidToolsCompactBand = {
            enabled = false,          -- independent on/off switch
            display = "always",       -- "always" | "mouseover"
            width   = CB_W,
            height  = CB_H,
            scale   = 1,
            -- Flat background overlay, matching the 9.0.7 Compact Band's own
            -- default (black at 62% opacity) -- see ApplyBackground.
            bgR     = 0,
            bgG     = 0,
            bgB     = 0,
            bgA     = 0.62,
            pos     = {},
        },
    },
}

local db
local function P()
    return db and db.profile and db.profile.raidToolsCompactBand
end

local function Enabled()
    local p = P()
    return p and p.enabled or false
end

local function Visibility()
    local p = P()
    local v = p and p.display
    if v ~= "mouseover" then v = "always" end
    return v
end

local function Scale()
    local p = P()
    return (p and p.scale) or 1
end

local function Width()
    local p = P()
    return math.max(CB_MIN_W, (p and p.width) or CB_W)
end

local function Height()
    local p = P()
    return math.max(CB_MIN_H, (p and p.height) or CB_H)
end

-- Reads through to the Raid Tools module's OWN profile, so Pull Timer and
-- Show Role Check stay a single setting shared by both windows. Falls back
-- to the stock defaults if Raid Tools has never initialized (its module can
-- be fully disabled while the Compact Band still runs on its own).
local function RT_P()
    local get = _G._EUI_RaidTools_DB
    local root = get and get()
    return root and root.profile and root.profile.raidTools
end

local function RoleCheckShown()
    local p = RT_P()
    return not p or p.showRoleCheck ~= false
end

-- Fixed pull durations for the Compact Band's PT button -- independent of
-- Raid Tools' own three-slot Pull Timer settings. Left Click pulls
-- PULL_BAND_FIRST, Shift + Left Click pulls PULL_BAND_SECOND; there is no
-- Ctrl slot here.
local PULL_BAND_FIRST  = 15
local PULL_BAND_SECOND = 30

-------------------------------------------------------------------------------
--  Fonts -- resolved through the same suite pipeline as every other panel.
-------------------------------------------------------------------------------
local FONT_KEY = "extras"
local fontOwners = {}
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

-------------------------------------------------------------------------------
--  Permission gating -- same rule as Raid Tools: ready check, role check,
--  the pull timer and the markers all need lead or assist in a raid.
-------------------------------------------------------------------------------
local function HasAssist()
    if not IsInGroup() then return true end
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end
local function AssistSuppressed()
    return IsInRaid() and not HasAssist()
end

-------------------------------------------------------------------------------
--  Tooltip -- own copy of the Data Bars-style tooltip Compact Band uses in
--  9.0.7 (bracketed title, action rows). Own frame name so it never collides
--  with Raid Tools' own tooltip if both are visible at once.
-------------------------------------------------------------------------------
local ShowTip, HideTip
do
    local tip, owner
    local rows = {}
    local TIP_PAD, TIP_ROW_GAP, TIP_COL_GAP, TIP_FONT_SIZE = 10, 3, 18, 12

    local function SetTipFont(fs)
        local path = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath(FONT_KEY)
        local _, _, flags = fs:GetFont()
        if not path and GameFontNormal then
            local fallbackPath, _, fallbackFlags = GameFontNormal:GetFont()
            path, flags = fallbackPath, fallbackFlags
        end
        if path then fs:SetFont(path, TIP_FONT_SIZE, flags or "") end
    end

    local function EnsureTip()
        if tip then return tip end
        tip = CreateFrame("Frame", "EllesmereUIRaidToolsCompactBandTip", UIParent)
        tip:SetFrameStrata("TOOLTIP")
        tip:SetFrameLevel(900)
        tip:SetClampedToScreen(true)
        tip:Hide()
        local bg = tip:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.067, 0.067, 0.067, 0.97)
        if EllesmereUI.PP and EllesmereUI.PP.CreateBorder then
            EllesmereUI.PP.CreateBorder(tip, 0, 0, 0, 0.9, 1, "OVERLAY", 7)
        end
        return tip
    end

    local function EnsureRow(i)
        local row = rows[i]
        if not row then
            row = {
                left = tip:CreateFontString(nil, "OVERLAY"),
                right = tip:CreateFontString(nil, "OVERLAY"),
            }
            rows[i] = row
        end
        SetTipFont(row.left)
        SetTipFont(row.right)
        return row
    end

    ShowTip = function(ownerFrame, title, actions)
        EnsureTip()
        owner = ownerFrame
        local count = #actions + 2
        local maxLeft, maxRight, totalH = 0, 0, 0
        for i = 1, count do
            local row = EnsureRow(i)
            row.left:ClearAllPoints()
            row.right:ClearAllPoints()
            row.left:SetWordWrap(false)
            row.right:SetWordWrap(false)
            row.left:SetWidth(0)
            row.right:SetWidth(0)

            if i == 1 then
                row.left:SetText("[" .. EllesmereUI.L(title) .. "]")
                row.right:SetText("")
                row.right:Hide()
                row._h = row.left:GetStringHeight() or TIP_FONT_SIZE
            elseif i == 2 then
                row.left:SetText("")
                row.right:SetText("")
                row.right:Hide()
                row._h = 4
            else
                local action = actions[i - 2]
                row.left:SetText(EllesmereUI.L(action[1]))
                row.right:SetText(EllesmereUI.L(action[2]))
                row.right:Show()
                row._h = math.max(row.left:GetStringHeight() or TIP_FONT_SIZE,
                    row.right:GetStringHeight() or TIP_FONT_SIZE)
            end
            row.left:SetTextColor(1, 1, 1, 1)
            row.right:SetTextColor(1, 1, 1, 1)
            row.left:Show()
            maxLeft = math.max(maxLeft, row.left:GetStringWidth() or 0)
            if row.right:IsShown() then
                maxRight = math.max(maxRight, row.right:GetStringWidth() or 0)
            end
            totalH = totalH + row._h + (i > 1 and TIP_ROW_GAP or 0)
        end
        for i = count + 1, #rows do
            rows[i].left:Hide()
            rows[i].right:Hide()
        end

        local innerW = maxLeft + (maxRight > 0 and TIP_COL_GAP + maxRight or 0)
        tip:SetSize(math.max(60, innerW + TIP_PAD * 2),
            math.max(24, totalH + TIP_PAD * 2))
        local y = -TIP_PAD
        for i = 1, count do
            local row = rows[i]
            row.left:SetPoint("TOPLEFT", tip, "TOPLEFT", TIP_PAD, y)
            if row.right:IsShown() then
                row.right:SetPoint("TOPRIGHT", tip, "TOPRIGHT", -TIP_PAD, y)
            end
            y = y - row._h - TIP_ROW_GAP
        end

        local level = 900
        if GameTooltip and GameTooltip.GetFrameLevel then
            local gameTipLevel = GameTooltip:GetFrameLevel()
            if gameTipLevel then level = math.max(level, gameTipLevel + 10) end
        end
        if tip:GetFrameLevel() < level then tip:SetFrameLevel(level) end
        tip:ClearAllPoints()
        local _, cy = ownerFrame:GetCenter()
        if cy and cy < UIParent:GetHeight() / 2 then
            tip:SetPoint("BOTTOM", ownerFrame, "TOP", 0, 6)
        else
            tip:SetPoint("TOP", ownerFrame, "BOTTOM", 0, -6)
        end
        tip:Show()
    end

    HideTip = function(ownerFrame)
        if not tip or (ownerFrame and owner ~= ownerFrame) then return end
        owner = nil
        tip:Hide()
    end
end

-------------------------------------------------------------------------------
--  Buttons
-------------------------------------------------------------------------------
local markerButtons = {}

-- Secure marker button -- identical attribute set to the 9.0.7 Compact Band
-- buttons. Built once, never touched again, so it stays usable in combat.
local function MakeMarkerButton(parent, index, kind)
    local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    b:SetSize(CB_ICON, CB_ICON)
    b:RegisterForClicks("AnyDown")
    b:SetAttribute("useOnKeyDown", true)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    b.icon = icon

    if kind == "marker" then
        local worldID = SYMBOL_TO_WORLD[index]
        b:SetAttribute("type1", "macro")
        -- No target selected: mark yourself instead of doing nothing, same
        -- fallback the main Raid Tools panel's target-marker row already
        -- uses (see MakeMarkerButton's "target" kind there).
        b:SetAttribute("macrotext1",
            (SLASH_TARGET_MARKER1 or "/tm") .. " [exists] !" .. index .. "; [@player] !" .. index)
        b:SetAttribute("type2", "worldmarker")
        b:SetAttribute("marker2", tostring(worldID))
        b:SetAttribute("action2", "set")
        b:SetAttribute("shift-type1", "macro")
        b:SetAttribute("shift-macrotext1",
            (SLASH_TARGET_MARKER1 or "/tm") .. " [exists] 0; [@player] 0")
        b:SetAttribute("shift-type2", "worldmarker")
        b:SetAttribute("shift-marker2", tostring(worldID))
        b:SetAttribute("shift-action2", "clear")
        b._worldID = worldID
    else -- "clear"
        b:SetAttribute("type1", "macro")
        b:SetAttribute("macrotext1", (SLASH_TARGET_MARKER1 or "/tm") .. " [exists] 0; [@player] 0")
        b:SetAttribute("type2", "macro")
        b:SetAttribute("macrotext2",
            (SLASH_CLEAR_WORLD_MARKER1 or "/cwm") .. " " .. (ALL or "All"))
    end

    if index == 0 then
        icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    else
        icon:SetTexture(MARKER_SHEET)
        SetRaidTargetIconTexture(icon, index)
    end

    icon:SetAlpha(0.8)
    b._baseAlpha = 0.8
    if kind == "marker" then
        local active = b:CreateTexture(nil, "OVERLAY")
        active:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, -2)
        active:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, -2)
        active:SetHeight(2)
        local ar, ag, ab = 0.05, 0.82, 0.62
        if EllesmereUI.GetAccentColor then ar, ag, ab = EllesmereUI.GetAccentColor() end
        active:SetColorTexture(ar, ag, ab, 0.95)
        active:Hide()
        b._activeLine = active
    end
    b:SetScript("OnEnter", function(self)
        if (self._baseAlpha or 0.8) >= 0.8 then self.icon:SetAlpha(1) end
        if kind == "clear" then
            ShowTip(self, "Clear Markers", CLEAR_TIP_ROWS)
        else
            ShowTip(self, MARKER_NAME[index] or "Raid Marker", MARKER_TIP_ROWS)
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(self._baseAlpha or 0.8)
        HideTip(self)
    end)

    markerButtons[#markerButtons + 1] = b
    return b
end

local function MakeActionButton(parent, label, tipBuilder, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(CB_ICON, CB_ICON)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", onClick)
    local fs = TrackFont(parent, EllesmereUI.MakeFont(b, 11, nil, 1, 1, 1), 11)
    fs:SetPoint("CENTER")
    fs:SetText(label)
    fs:SetAlpha(0.8)
    b.label = fs
    b:SetScript("OnEnter", function(self)
        self.label:SetAlpha(1)
        local title, actions = tipBuilder()
        ShowTip(self, title, actions)
    end)
    b:SetScript("OnLeave", function(self)
        self.label:SetAlpha(0.8)
        HideTip(self)
    end)
    return b
end

-------------------------------------------------------------------------------
--  Frame -- a PLAIN shell (see the combat-model note in the header). Content
--  parents straight to it; there is no separate holder because nothing else
--  ever shares this frame.
-------------------------------------------------------------------------------
local shell = {}
local readyButton, pullButton, divider
local markerButtonList = {}

local function LayoutMarkers()
    if not shell.frame or #markerButtonList < 2 then return end
    local width = shell.frame:GetWidth()
    if not width or width < CB_MIN_W then return end

    local utilityCount = pullButton and pullButton:IsShown() and 2 or 1
    local utilityWidth = utilityCount * CB_ICON + (utilityCount - 1) * CB_GAP
    local firstLeft = CB_PAD
    local lastLeft = width - CB_PAD - utilityWidth - CB_DIVIDER_OFFSET - CB_GAP - CB_ICON
    local stride = (lastLeft - firstLeft) / (#markerButtonList - 1)

    for i, button in ipairs(markerButtonList) do
        button:ClearAllPoints()
        local x = math.floor(firstLeft + (i - 1) * stride + 0.5)
        button:SetPoint("LEFT", shell.frame, "LEFT", x, 0)
    end
end

local function RefreshPullState()
    if not pullButton then return end
    -- Fixed Left/Shift+Left durations (see PULL_BAND_FIRST/SECOND) --
    -- the button is always available, no configurable on/off slots here.
    pullButton:Show()
    if readyButton then
        readyButton:Show()
        readyButton:ClearAllPoints()
        readyButton:SetPoint("RIGHT", shell.frame, "RIGHT", -CB_PAD, 0)
        pullButton:ClearAllPoints()
        pullButton:SetPoint("RIGHT", readyButton, "LEFT", -CB_GAP, 0)
    end
    if divider then
        divider:ClearAllPoints()
        divider:SetPoint("TOP", pullButton, "TOPLEFT", -CB_DIVIDER_OFFSET, -2)
        divider:SetPoint("BOTTOM", pullButton, "BOTTOMLEFT", -CB_DIVIDER_OFFSET, 2)
    end
    LayoutMarkers()
end

local function RefreshMarkerState()
    for _, b in ipairs(markerButtonList) do
        local active = b._worldID and IsRaidMarkerActive and IsRaidMarkerActive(b._worldID)
        if b.icon.SetDesaturated then b.icon:SetDesaturated(active and true or false) end
        if b._activeLine then b._activeLine:SetShown(active and true or false) end
    end
end

local lastAssist
local function RefreshPermissions(force)
    local assist = HasAssist()
    if not force and assist == lastAssist then return end
    lastAssist = assist
    for _, b in ipairs(markerButtonList) do
        b._baseAlpha = assist and 0.8 or 0.4
        b.icon:SetAlpha(b._baseAlpha)
    end
end

-------------------------------------------------------------------------------
--  Background -- the 9.0.7 Compact Band is NOT fully transparent: Raid
--  Tools' own ApplyShellMaterial hides the art texture, title bar and
--  border in compact mode, but always keeps a flat black overlay
--  (SetColorTexture(0, 0, 0, 0.62)) behind the buttons. This reproduces
--  that overlay -- same 0.62 default -- as its own texture, with the color
--  and opacity both exposed on the options page.
-------------------------------------------------------------------------------
local Apply -- forward

local function ApplyBackground()
    local f = shell.frame
    if not f or not f._bg then return end
    local p = P()
    local r = (p and p.bgR) or 0
    local g = (p and p.bgG) or 0
    local b = (p and p.bgB) or 0
    local a = (p and p.bgA) or 0.62
    f._bg:SetColorTexture(r, g, b, a)
end

-------------------------------------------------------------------------------
--  Build -- runs once, on first Enable.
-------------------------------------------------------------------------------
local function Build()
    if shell.frame then return end

    local f = CreateFrame("Frame", "EllesmereUIRaidToolsCompactBandStandalone", UIParent)
    f:SetSize(CB_W, CB_H)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:Hide()
    shell.frame = f
    fontOwners[#fontOwners + 1] = f

    -- Flat black overlay, same as the 9.0.7 Compact Band shell (see the
    -- note above ApplyBackground). Color/opacity are user-configurable.
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    f._bg = bg
    ApplyBackground()

    for _, index in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8 }) do
        local b = MakeMarkerButton(f, index, "marker")
        markerButtonList[#markerButtonList + 1] = b
    end
    local clear = MakeMarkerButton(f, 0, "clear")
    markerButtonList[#markerButtonList + 1] = clear

    readyButton = MakeActionButton(f, "RC", function()
        if RoleCheckShown() then
            return "Ready Check", {
                { "Left Click", "Ready Check" },
                { "Right Click", "Role Check" },
            }
        end
        return "Ready Check", { { "Left Click", "Ready Check" } }
    end, function(_, button)
        if button == "RightButton" then
            if RoleCheckShown() then InitiateRolePoll() end
        else
            DoReadyCheck()
        end
    end)

    pullButton = MakeActionButton(f, "PT", function()
        return "Pull Timer", {
            { "Left Click", "Pull " .. PULL_BAND_FIRST },
            { "Shift + Left Click", "Pull " .. PULL_BAND_SECOND },
            { "Right Click", "Stop pull timer" },
        }
    end, function(_, button)
        local BossModPullHandler = function()
            return SlashCmdList.BIGWIGSPULL or SlashCmdList.DEADLYBOSSMODSPULL
        end
        local function ChatLocked()
            return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
                and C_ChatInfo.InChatMessagingLockdown()
        end
        if button == "RightButton" then
            local handler = BossModPullHandler()
            if handler then handler("0") end
            if not ChatLocked() then C_PartyInfo.DoCountdown(0) end
            return
        end
        local secs = IsShiftKeyDown() and PULL_BAND_SECOND or PULL_BAND_FIRST
        local handler = BossModPullHandler()
        if handler then handler(tostring(secs)) end
        if ChatLocked() then
            EllesmereUI.Print("|cff0cd29fEllesmereUI:|r " .. EllesmereUI.L(
                "In-game countdown unavailable in combat; the boss mod pull timer still started."))
            return
        end
        C_PartyInfo.DoCountdown(secs)
    end)

    readyButton:SetPoint("RIGHT", f, "RIGHT", -CB_PAD, 0)
    pullButton:SetPoint("RIGHT", readyButton, "LEFT", -CB_GAP, 0)

    divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.10)
    divider:SetWidth(1)
    divider:SetPoint("TOP", pullButton, "TOPLEFT", -CB_DIVIDER_OFFSET, -2)
    divider:SetPoint("BOTTOM", pullButton, "BOTTOMLEFT", -CB_DIVIDER_OFFSET, 2)

    RefreshPullState()
    RefreshMarkerState()
    ApplyFonts()
end

-------------------------------------------------------------------------------
--  Position -- same CENTER/CENTER + unlock-anchor convention as the rest of
--  the suite (see EllesmereUIQoL_RaidTools.lua's ApplySectionPosition for the
--  full rationale).
-------------------------------------------------------------------------------
local UNLOCK_KEY = "EUI_RaidToolsCompactBandStandalone"

local function DefaultPos()
    local MARGIN = 20
    local s = Scale()
    return { point = "TOPLEFT", relPoint = "TOPLEFT", x = MARGIN / s, y = -MARGIN / s }
end

local function ApplyPosition()
    local f = shell.frame
    if not f then return end
    if EllesmereUI._unlockActive then return end -- unlock mode owns live position

    local p = P()
    local pos = (p and p.pos) or DefaultPos()
    if not pos.point then pos = DefaultPos() end
    if EllesmereUI.ApplyCenterPosition
       and pos.point == "CENTER" and pos.relPoint == "CENTER" then
        if EllesmereUI.ApplyCenterPosition(UNLOCK_KEY, pos) then return end
    end
    if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(UNLOCK_KEY) then
        return
    end
    f:ClearAllPoints()
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
end

-------------------------------------------------------------------------------
--  Mouseover fade -- same throttled-poll pattern as Raid Tools' own display
--  option, so both windows feel consistent if the user runs both.
-------------------------------------------------------------------------------
local function ApplyFade()
    local f = shell.frame
    if not f then return end
    local faded = Visibility() == "mouseover"
    local hovered = f:IsMouseOver()
    f:SetAlpha((not faded or hovered) and 1 or 0)
end

local fadeTicker = CreateFrame("Frame")
do
    local acc = 0
    fadeTicker:SetScript("OnUpdate", function(self, elapsed)
        if not shell.frame or not shell.frame:IsShown() or Visibility() ~= "mouseover" then return end
        acc = acc + elapsed
        if acc < 0.05 then return end
        acc = 0
        ApplyFade()
    end)
end

-------------------------------------------------------------------------------
--  Apply -- the single entry point; safe to call any time (the shell is a
--  plain frame, never protected, so nothing here is combat-restricted).
-------------------------------------------------------------------------------
function Apply()
    if not db then return end
    if not Enabled() then
        if shell.frame then shell.frame:Hide() end
        return
    end
    Build()
    shell.frame:SetSize(Width(), Height())
    shell.frame:SetScale(Scale())
    ApplyPosition()
    ApplyBackground()
    shell.frame:Show()
    ApplyFade()
    RefreshPullState()
    RefreshMarkerState()
    RefreshPermissions(true)
    ApplyFonts()
end
_G._EUI_RaidToolsCompactBand_Apply = Apply

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if not Enabled() then return end
    if event == "RAID_TARGET_UPDATE" then
        RefreshMarkerState()
    else
        RefreshPermissions()
    end
end)
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("PARTY_LEADER_CHANGED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("RAID_TARGET_UPDATE")

-------------------------------------------------------------------------------
--  Unlock Mode registration -- lets the band be dragged and resized the same
--  way every other movable EllesmereUI element is (Global Settings > Unlock,
--  or /unlock).
-------------------------------------------------------------------------------
local unlockRegistered
local function RegisterUnlock()
    if unlockRegistered then return end
    local MK = EllesmereUI.MakeUnlockElement
    if not MK then return end
    unlockRegistered = true

    EllesmereUI:RegisterUnlockElements({
        MK({
            key   = UNLOCK_KEY,
            label = "Compact Band",
            group = "Raid Tools",
            order = 545,
            isHidden = function() return not Enabled() end,
            getFrame = function()
                if not Enabled() then return nil end
                Build()
                return shell.frame
            end,
            getSize = function()
                local f = shell.frame
                local s = Scale()
                if f then return f:GetWidth() * s, f:GetHeight() * s end
                return Width() * s, Height() * s
            end,
            setWidth = function(_, newW)
                local p = P(); if not (p and newW) then return end
                local PPb = EllesmereUI and EllesmereUI.PP
                p.width = math.max(CB_MIN_W, PPb and PPb.Snap(newW) or math.floor(newW + 0.5))
                if shell.frame then shell.frame:SetWidth(Width()); RefreshPullState() end
            end,
            setHeight = function(_, newH)
                local p = P(); if not (p and newH) then return end
                local PPb = EllesmereUI and EllesmereUI.PP
                p.height = math.max(CB_MIN_H, PPb and PPb.Snap(newH) or math.floor(newH + 0.5))
                if shell.frame then shell.frame:SetHeight(Height()) end
            end,
            savePos = function(_, point, relPoint, x, y)
                if not point then return end
                local p = P(); if not p then return end
                if EllesmereUI.ConvertToCenterPos then
                    point, relPoint, x, y =
                        EllesmereUI.ConvertToCenterPos(UNLOCK_KEY, point, relPoint, x, y)
                end
                p.pos = { point = point, relPoint = relPoint, x = x, y = y }
                if not EllesmereUI._unlockActive then ApplyPosition() end
            end,
            loadPos = function() return P() and P().pos end,
            clearPos = function()
                local p = P(); if p then p.pos = {} end
            end,
            applyPos = ApplyPosition,
        }),
    }, "EllesmereUIQoL")
end

-------------------------------------------------------------------------------
--  Init -- same shape as every other QoL feature: take the shared QoL DB
--  handle on PLAYER_LOGIN, publish it, then start. Apply() is a no-op for
--  anyone on the default "disabled" state.
-------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not (EllesmereUI and EllesmereUI.Lite and EllesmereUI.Lite.NewDB) then return end
    db = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", DB_DEFAULTS, true)
    _G._EUI_RaidToolsCompactBand_DB = function() return db end
    RegisterUnlock()
    Apply()
end)
