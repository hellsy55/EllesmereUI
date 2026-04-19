-------------------------------------------------------------------------------
--  EllesmereUIDragonRiding.lua  —  Skyriding HUD for EllesmereUI
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EDR = EllesmereUI.Lite.NewAddon(ADDON_NAME)
ns.EDR = EDR

-- Upvalues
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local format = string.format
local IsMounted = IsMounted
local C_PlayerInfo = C_PlayerInfo
local C_Spell = C_Spell
local C_MountJournal = C_MountJournal
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local UnitAffectingCombat = UnitAffectingCombat
local GetCVar = GetCVar
local GetTime = GetTime

-- Spell IDs
local SPELL = {
    SKYWARD_ASCENT  = 372610,
    SECOND_WIND     = 425782,
    WHIRLING_SURGE  = 361584,
}

-- Pip counts
local SKYRIDING_PIPS  = 6
local SECONDWIND_PIPS = 3

-- Database defaults
local DB_DEFAULTS = {
    profile = {
        enabled          = true,
        hideInCombat     = false,

        width            = 240,
        speedHeight      = 14,
        skyridingHeight  = 10,
        secondWindHeight = 6,
        gap              = 2,
        stackSpacing     = 2,

        borderEnabled   = true,
        borderThickness = 1,
        borderColor     = { r = 0.0, g = 0.0, b = 0.0, a = 1.0 },

        maxSpeed          = 1300,
        thrillThreshold   = 789,
        thrillColorToggle = true,
        normalColor       = { r = 0.055, g = 0.667, b = 0.761, a = 1.0 },  -- 0EAAC2 cyan-blue
        thrillColor       = { r = 0.902, g = 0.494, b = 0.133, a = 1.0 },  -- E67E22 warm orange
        speedBarBg        = { r = 0.10, g = 0.10, b = 0.10, a = 0.80 },
        tickColor         = { r = 1.00, g = 1.00, b = 1.00, a = 0.80 },

        speedText = {
            enabled = true,
            justify = "CENTER",
            size    = 12,
            offsetX = 0,
            offsetY = 0,
        },

        skyridingFilled        = { r = 0.047, g = 0.824, b = 0.624, a = 1.0 },  -- 0CD29F EllesmereUI teal
        skyridingBg            = { r = 0.10, g = 0.10, b = 0.10, a = 0.80 },

        secondWindFilled        = { r = 0.902, g = 0.706, b = 0.133, a = 1.0 },  -- E6B422 split-complementary amber
        secondWindBg            = { r = 0.10, g = 0.10, b = 0.10, a = 0.80 },

        whirlingSurgeText = {
            enabled = true,
            justify = "CENTER",
            size    = 12,
            offsetX = 0,
            offsetY = 0,
        },

        unlockPos = nil,
    },
}

-- Database handle (populated in OnInitialize)
local db

-- Frames (populated in Build; see Task 4)
local rootFrame, speedBar, stackFrame, swFrame, wsIcon

-- Dirty flags
local skyridingDirty  = true
local secondWindDirty = true
local whirlingDirty   = true
local thrillActive    = false
local shouldShow      = false

-- OnUpdate state
local lastSpeedApplied  = -1
local lastCdStart, lastCdDur = -1, -1
local lastSkyCur, lastSkyProgress = -1, -1
local lastSwCur,  lastSwProgress  = -1, -1
-- UPDATE_THROTTLE is computed from the user's maxFPS cvar in OnEnable.
-- 4 × frameTime gives a HUD-smooth cadence that scales with the user's
-- rendering cadence: 60 fps cap → 67 ms, 144 → 28 ms, 30 → 133 ms.
-- Initial default is 67 ms (15 Hz) in case OnEnable hasn't run yet.
local UPDATE_THROTTLE   = 0.067
local elapsed           = 0

local function ComputeUpdateThrottle()
    local maxFPS = tonumber(GetCVar and GetCVar("maxFPS") or 0) or 0
    if maxFPS <= 0 then maxFPS = 60 end  -- cvar 0 = unlimited; use 60 as baseline
    return 4 / maxFPS
end

-- Skyriding speed: C_PlayerInfo.GetGlidingInfo() returns the engine's own
-- forwardSpeed (yards/sec) during skyriding — reliable and jitter-free.
-- We apply a light EMA to avoid the bar snapping on sudden velocity changes.
local smoothedSpeed   = 0
local SPEED_EMA_ALPHA = 0.25   -- blend factor: 0 = never moves, 1 = instant snap

-- Returns (isGliding, smoothedSpeed). When isGliding is false, callers can
-- skip speed-bar updates entirely to save per-frame work.
local function GetSkyridingSpeed()
    local isGliding, _, forwardSpeed = C_PlayerInfo.GetGlidingInfo()
    if not isGliding then
        -- Decay to 0 smoothly when we stop gliding; don't hold stale speed.
        smoothedSpeed = smoothedSpeed * (1 - SPEED_EMA_ALPHA)
        return false, smoothedSpeed
    end
    local raw = forwardSpeed or 0
    smoothedSpeed = smoothedSpeed + SPEED_EMA_ALPHA * (raw - smoothedSpeed)
    return true, smoothedSpeed
end

-------------------------------------------------------------------------------
--  Stubs filled in by later tasks
-------------------------------------------------------------------------------
local function Build() end
local function Rebuild() end
local function Redraw() end
local function UpdateVisibility() end
local function OnUpdate() end
local function ApplyPos() end
local function RegisterUnlockElements() end

-------------------------------------------------------------------------------
--  Visibility detection
-------------------------------------------------------------------------------

-- Is the player actively in skyriding (dynamic-flight) mode?
-- Uses C_PlayerInfo.GetGlidingInfo()'s `canGlide` return, which correctly
-- reflects the player's current flight-style choice (a skyriding-capable
-- mount flown in "standard flying" mode reports canGlide = false).
local function IsOnSkyridingMount()
    if not IsMounted() then return false end
    if not C_PlayerInfo or not C_PlayerInfo.GetGlidingInfo then return false end
    local _, canGlide = C_PlayerInfo.GetGlidingInfo()
    return canGlide == true
end

function UpdateVisibility()
    if not rootFrame then return end
    local p = db and db.profile
    if not p or not p.enabled then
        shouldShow = false
        rootFrame:Hide()
        return
    end
    -- Unlock-mode override: always visible while positioning
    if EllesmereUI and EllesmereUI._unlockActive then
        shouldShow = true
        rootFrame:Show()
        return
    end
    local onSky = IsOnSkyridingMount()
    local inCombat = UnitAffectingCombat("player")
    local hideCombat = p.hideInCombat and inCombat
    shouldShow = onSky and not hideCombat
    rootFrame:SetShown(shouldShow)
end

-------------------------------------------------------------------------------
--  OnUpdate handler
-------------------------------------------------------------------------------

-- Applies pip state to `pips[1..pipCount]` with minimal UI writes.
-- - Full repaint when `cur` differs from `lastCur` (colors + values).
-- - Incremental update when only the recharging pip's `progress` changed.
-- Returns the new lastCur, lastProgress for caller to persist.
local function ApplyPipRow(pips, pipCount, cur, maxC, progress,
                            lastCur, lastProgress,
                            filled, bgAlpha)
    if cur ~= lastCur then
        for i = 1, pipCount do
            local pip = pips[i]
            if i <= cur then
                pip:SetValue(1)
                pip:SetStatusBarColor(filled.r, filled.g, filled.b, 1)
            elseif i == cur + 1 and cur < maxC then
                pip:SetValue(progress)
                pip:SetStatusBarColor(filled.r, filled.g, filled.b, bgAlpha)
            else
                pip:SetValue(0)
                pip:SetStatusBarColor(filled.r, filled.g, filled.b, 1)
            end
        end
        return cur, progress
    elseif cur < maxC and abs(progress - lastProgress) > 0.005 then
        local pip = pips[cur + 1]
        if pip then pip:SetValue(progress) end
        return cur, progress
    end
    return lastCur, lastProgress
end

local function FormatSpeedText(speedPct)
    return format("%d%%", floor(speedPct + 0.5))
end

local function FormatCooldownText(remaining)
    if remaining >= 10 then return format("%d", floor(remaining + 0.5))
    elseif remaining >= 1 then return format("%d", floor(remaining))
    else return format("%.1f", remaining) end
end

function OnUpdate(self, dt)
    if not shouldShow then return end
    elapsed = elapsed + dt
    if elapsed < UPDATE_THROTTLE then return end
    elapsed = 0

    local p = db.profile

    -- Speed bar
    local gliding, curSpeed = GetSkyridingSpeed()      -- yards/sec (engine gliding speed)
    local runSpeed = 7.0                              -- base run speed
    local speedPct = curSpeed / runSpeed * 100        -- in percent
    local frac = (p.maxSpeed > 0) and (speedPct / p.maxSpeed) or 0
    frac = max(0, min(1, frac))
    if frac ~= lastSpeedApplied then
        speedBar:SetValue(frac)
        if p.speedText.enabled ~= false then
            speedBar.text:SetText(FormatSpeedText(speedPct))
        end
        local aboveThrill = (speedPct >= (p.thrillThreshold or 0))
        local c = (p.thrillColorToggle and aboveThrill) and p.thrillColor or p.normalColor
        speedBar:SetStatusBarColor(c.r, c.g, c.b, c.a)
        lastSpeedApplied = frac
    end

    -- Skyriding pips
    if skyridingDirty then
        local info = C_Spell.GetSpellCharges(SPELL.SKYWARD_ASCENT)
        local cur  = info and info.currentCharges or 0
        local maxC = info and info.maxCharges or SKYRIDING_PIPS
        local progress = 0
        if info and info.cooldownDuration and info.cooldownDuration > 0 then
            local e = GetTime() - (info.cooldownStartTime or 0)
            progress = max(0, min(1, e / info.cooldownDuration))
        end
        lastSkyCur, lastSkyProgress = ApplyPipRow(
            stackFrame.pips, SKYRIDING_PIPS, cur, maxC, progress,
            lastSkyCur, lastSkyProgress,
            p.skyridingFilled, 0.4)
        skyridingDirty = (cur < maxC)
    end

    -- Second Wind pips (mirror of skyriding rule)
    if secondWindDirty then
        local info = C_Spell.GetSpellCharges(SPELL.SECOND_WIND)
        local cur  = info and info.currentCharges or 0
        local maxC = info and info.maxCharges or SECONDWIND_PIPS
        local progress = 0
        if info and info.cooldownDuration and info.cooldownDuration > 0 then
            local e = GetTime() - (info.cooldownStartTime or 0)
            progress = max(0, min(1, e / info.cooldownDuration))
        end
        lastSwCur, lastSwProgress = ApplyPipRow(
            swFrame.pips, SECONDWIND_PIPS, cur, maxC, progress,
            lastSwCur, lastSwProgress,
            p.secondWindFilled, 0.4)
        secondWindDirty = (cur < maxC)
    end

    -- Whirling Surge cooldown text + swipe priming
    if whirlingDirty then
        local info = C_Spell.GetSpellCooldown(SPELL.WHIRLING_SURGE)
        local start = info and info.startTime or 0
        local dur   = info and info.duration  or 0
        -- Filter out the GCD (~1.5s). Whirling Surge is 30s; any real CD is well above 1.5.
        if dur > 1.5 then
            if start ~= lastCdStart or dur ~= lastCdDur then
                wsIcon.cd:SetCooldown(start, dur)
                lastCdStart, lastCdDur = start, dur
            end
            local remaining = start + dur - GetTime()
            if remaining > 0 then
                if p.whirlingSurgeText.enabled ~= false then
                    wsIcon.text:SetText(FormatCooldownText(remaining))
                end
                whirlingDirty = true  -- keep polling while on CD
            else
                wsIcon.text:SetText("")
                whirlingDirty = false
            end
        else
            if lastCdDur ~= 0 then
                wsIcon.cd:Clear()
                wsIcon.text:SetText("")
                lastCdStart, lastCdDur = 0, 0
            end
            whirlingDirty = false
        end
    end
end

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
function EDR:OnInitialize()
    db = EllesmereUI.Lite.NewDB("EllesmereUIDragonRidingDB", DB_DEFAULTS)
    _G._EDR_AceDB = db
end

function EDR:OnEnable()
    if not db then return end
    UPDATE_THROTTLE = ComputeUpdateThrottle()
    -- Always Build so toggling "enabled" via options takes effect without a /reload.
    -- UpdateVisibility hides the frame when p.enabled is false.
    Build()
    rootFrame:SetScript("OnUpdate", OnUpdate)

    local evtFrame = CreateFrame("Frame")
    evtFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    evtFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    evtFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
    evtFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    evtFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    evtFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
    evtFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    evtFrame:SetScript("OnEvent", function(_, event)
        if event == "SPELL_UPDATE_CHARGES" then
            skyridingDirty = true
            secondWindDirty = true
            return
        elseif event == "SPELL_UPDATE_COOLDOWN" then
            whirlingDirty = true
            skyridingDirty = true
            secondWindDirty = true
            return
        elseif event == "PLAYER_ENTERING_WORLD" then
            skyridingDirty = true
            secondWindDirty = true
            whirlingDirty = true
        end
        -- The four events that actually change visibility fall through:
        -- PLAYER_ENTERING_WORLD, PLAYER_MOUNT_DISPLAY_CHANGED,
        -- PLAYER_REGEN_ENABLED, PLAYER_REGEN_DISABLED.
        UpdateVisibility()
    end)

    UpdateVisibility()

    C_Timer.After(0.5, function()
        RegisterUnlockElements()
        ApplyPos()
    end)
end

-- Expose DB accessor for options file
function EDR:DB() return db and db.profile end

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function ApplyFont(fs, size)
    if not fs then return end
    local font = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or "Fonts/FRIZQT__.TTF"
    local flag = EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag() or ""
    fs:SetFont(font, size or 12, flag)
    if flag == "" then
        fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

local function CreateSolidTexture(parent, layer, sublevel, r, g, b, a)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    tex:SetColorTexture(r or 0, g or 0, b or 0, a or 1)
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
    return tex
end

-- List of frames that carry a border. Populated during Build().
local borderedFrames = {}

local function EnsureBorder(frame)
    if not frame or frame._edrBorderAdded then return end
    if not (EllesmereUI and EllesmereUI.PP and EllesmereUI.PP.CreateBorder) then return end
    -- Initial color/size placeholders; real values applied in ApplyBordersAll.
    EllesmereUI.PP.CreateBorder(frame, 0, 0, 0, 1, 1, "OVERLAY", 7)
    frame._edrBorderAdded = true
    borderedFrames[#borderedFrames + 1] = frame
end

local function ApplyBordersAll()
    local PP = EllesmereUI and EllesmereUI.PP
    if not PP then return end
    local p = db.profile
    local c = p.borderColor
    local thick = p.borderThickness or 1
    for _, f in ipairs(borderedFrames) do
        if p.borderEnabled then
            PP.UpdateBorder(f, thick, c.r, c.g, c.b, c.a)
            PP.ShowBorder(f)
        else
            PP.HideBorder(f)
        end
    end
end

-- Frame constructors (each returns a detached frame; anchoring is done in Rebuild)
local function CreateSpeedBar(parent)
    local f = CreateFrame("StatusBar", nil, parent)
    f:SetMinMaxValues(0, 1)
    f:SetValue(0)
    f:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    f.bg   = CreateSolidTexture(f, "BACKGROUND", 0)
    f.bg:SetAllPoints(f)
    f.tick = CreateSolidTexture(f, "OVERLAY", 5)
    f.text = f:CreateFontString(nil, "OVERLAY")
    return f
end

local function CreateStackFrame(parent, pipCount)
    local f = CreateFrame("Frame", nil, parent)
    f.pips = {}
    for i = 1, pipCount do
        local pip = CreateFrame("StatusBar", nil, f)
        pip:SetMinMaxValues(0, 1)
        pip:SetValue(0)
        pip:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        pip.bg = CreateSolidTexture(pip, "BACKGROUND", 0)
        pip.bg:SetAllPoints(pip)
        f.pips[i] = pip
    end
    return f
end

local function CreateWhirlingSurgeIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints(f)
    local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(SPELL.WHIRLING_SURGE)
    local iconFile = info and (info.iconID or info.icon) or 135860
    f.tex:SetTexture(iconFile)
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints(f)
    f.cd:SetDrawEdge(false)
    f.cd:SetHideCountdownNumbers(true)  -- we draw our own
    -- Text overlay frame sits above the cooldown swipe child frame
    f.textFrame = CreateFrame("Frame", nil, f)
    f.textFrame:SetAllPoints(f)
    f.textFrame:SetFrameLevel(f.cd:GetFrameLevel() + 1)
    f.text = f.textFrame:CreateFontString(nil, "OVERLAY")
    return f
end

function Build()
    if rootFrame then return end  -- idempotent
    rootFrame = CreateFrame("Frame", "EllesmereUIDragonRidingAnchor", UIParent)
    rootFrame:SetFrameStrata("MEDIUM")
    rootFrame:Hide()
    -- Default spawn point — Rebuild()/ApplyPos() will overwrite if unlockPos is set.
    if not (db and db.profile and db.profile.unlockPos) then
        rootFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    speedBar   = CreateSpeedBar(rootFrame)
    EnsureBorder(speedBar)

    stackFrame = CreateStackFrame(rootFrame, SKYRIDING_PIPS)
    for i = 1, SKYRIDING_PIPS do EnsureBorder(stackFrame.pips[i]) end

    swFrame    = CreateStackFrame(rootFrame, SECONDWIND_PIPS)
    for i = 1, SECONDWIND_PIPS do EnsureBorder(swFrame.pips[i]) end

    wsIcon     = CreateWhirlingSurgeIcon(rootFrame)
    EnsureBorder(wsIcon)

    Rebuild()
end

local function ComputePipLayout(totalWidth, pipCount, spacing)
    -- Pixel-perfect pip geometry: floor pipWidth, distribute remainder.
    local widthAvail = math.max(0, totalWidth - (pipCount - 1) * spacing)
    local pipWidth   = floor(widthAvail / pipCount)
    local remainder  = widthAvail - pipWidth * pipCount  -- pixels to sprinkle
    return pipWidth, remainder
end

function Rebuild()
    if not rootFrame then return end
    local p = db.profile

    -- Root size
    local skyRowW = p.width
    local totalH   = p.secondWindHeight + p.gap + p.skyridingHeight + p.gap + p.speedHeight
    local iconSize = totalH
    local totalW   = skyRowW + p.gap + iconSize
    rootFrame:SetSize(totalW, totalH)

    -- Speed bar (bottom-left)
    speedBar:ClearAllPoints()
    speedBar:SetPoint("BOTTOMLEFT", rootFrame, "BOTTOMLEFT", 0, 0)
    speedBar:SetSize(p.width, p.speedHeight)

    -- Skyriding row (above speed bar)
    stackFrame:ClearAllPoints()
    stackFrame:SetPoint("BOTTOMLEFT", speedBar, "TOPLEFT", 0, p.gap)
    stackFrame:SetSize(p.width, p.skyridingHeight)

    local pipW, rem = ComputePipLayout(p.width, SKYRIDING_PIPS, p.stackSpacing)
    local x = 0
    for i = 1, SKYRIDING_PIPS do
        local thisW = pipW + (i <= rem and 1 or 0)
        local pip = stackFrame.pips[i]
        pip:ClearAllPoints()
        pip:SetPoint("TOPLEFT", stackFrame, "TOPLEFT", x, 0)
        pip:SetSize(thisW, p.skyridingHeight)
        x = x + thisW + p.stackSpacing
    end

    -- Second Wind row (above skyriding row, centered over skyriding row)
    swFrame:ClearAllPoints()
    swFrame:SetPoint("BOTTOM", stackFrame, "TOP", 0, p.gap)
    swFrame:SetSize(p.width, p.secondWindHeight)  -- row width == skyriding row width

    local swPipW, swRem = ComputePipLayout(p.width, SECONDWIND_PIPS, p.stackSpacing)
    x = 0
    for i = 1, SECONDWIND_PIPS do
        local thisW = swPipW + (i <= swRem and 1 or 0)
        local pip = swFrame.pips[i]
        pip:ClearAllPoints()
        pip:SetPoint("TOPLEFT", swFrame, "TOPLEFT", x, 0)
        pip:SetSize(thisW, p.secondWindHeight)
        x = x + thisW + p.stackSpacing
    end

    -- Whirling Surge icon (right of speed + skyriding rows)
    wsIcon:ClearAllPoints()
    wsIcon:SetPoint("BOTTOMLEFT", speedBar, "BOTTOMRIGHT", p.gap, 0)
    wsIcon:SetSize(iconSize, iconSize)

    -- Colors / text
    Redraw()

    -- Apply saved position
    if p.unlockPos then
        local pos = p.unlockPos
        rootFrame:ClearAllPoints()
        rootFrame:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or pos.point or "CENTER",
            pos.x or 0, pos.y or 0)
    end

    UpdateVisibility()
end

function Redraw()
    if not rootFrame then return end
    local p = db.profile

    -- Speed bar colors
    local c = p.normalColor
    speedBar:SetStatusBarColor(c.r, c.g, c.b, c.a)
    speedBar.bg:SetColorTexture(p.speedBarBg.r, p.speedBarBg.g, p.speedBarBg.b, p.speedBarBg.a)
    -- Tick position
    local tickFrac = (p.thrillThreshold or 0) / (p.maxSpeed > 0 and p.maxSpeed or 1)
    tickFrac = max(0, min(1, tickFrac))
    speedBar.tick:ClearAllPoints()
    speedBar.tick:SetPoint("TOP",    speedBar, "TOPLEFT",    p.width * tickFrac, 0)
    speedBar.tick:SetPoint("BOTTOM", speedBar, "BOTTOMLEFT", p.width * tickFrac, 0)
    speedBar.tick:SetWidth(2)
    speedBar.tick:SetColorTexture(p.tickColor.r, p.tickColor.g, p.tickColor.b, p.tickColor.a)

    -- Speed text
    ApplyFont(speedBar.text, p.speedText.size)
    speedBar.text:ClearAllPoints()
    speedBar.text:SetPoint(p.speedText.justify or "CENTER", speedBar,
        p.speedText.justify or "CENTER",
        p.speedText.offsetX or 0, p.speedText.offsetY or 0)
    speedBar.text:SetJustifyH(p.speedText.justify or "CENTER")
    speedBar.text:SetShown(p.speedText.enabled ~= false)

    -- Skyriding pips default state
    for i = 1, SKYRIDING_PIPS do
        local pip = stackFrame.pips[i]
        pip:SetStatusBarColor(p.skyridingFilled.r, p.skyridingFilled.g, p.skyridingFilled.b, 1)
        pip.bg:SetColorTexture(p.skyridingBg.r, p.skyridingBg.g, p.skyridingBg.b, p.skyridingBg.a)
    end

    -- Second Wind pips default state
    for i = 1, SECONDWIND_PIPS do
        local pip = swFrame.pips[i]
        pip:SetStatusBarColor(p.secondWindFilled.r, p.secondWindFilled.g, p.secondWindFilled.b, 1)
        pip.bg:SetColorTexture(p.secondWindBg.r, p.secondWindBg.g, p.secondWindBg.b, p.secondWindBg.a)
    end

    -- Whirling Surge cooldown text
    ApplyFont(wsIcon.text, p.whirlingSurgeText.size)
    wsIcon.text:ClearAllPoints()
    wsIcon.text:SetPoint(p.whirlingSurgeText.justify or "CENTER", wsIcon,
        p.whirlingSurgeText.justify or "CENTER",
        p.whirlingSurgeText.offsetX or 0, p.whirlingSurgeText.offsetY or 0)
    wsIcon.text:SetJustifyH(p.whirlingSurgeText.justify or "CENTER")
    wsIcon.text:SetShown(p.whirlingSurgeText.enabled ~= false)

    -- Borders
    ApplyBordersAll()

    -- Mark all dynamic state dirty so OnUpdate re-applies at next tick
    skyridingDirty  = true
    secondWindDirty = true
    whirlingDirty   = true
    -- Force next OnUpdate to do a full pip repaint (colors may have changed)
    lastSkyCur, lastSkyProgress = -1, -1
    lastSwCur,  lastSwProgress  = -1, -1
    lastCdStart, lastCdDur      = -1, -1
end

-------------------------------------------------------------------------------
--  Unlock mode
-------------------------------------------------------------------------------
local function SavePos(_, point, relPoint, x, y)
    if not point then return end
    local p = db and db.profile
    if not p then return end
    p.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y }
    if not EllesmereUI._unlockActive and rootFrame then
        rootFrame:ClearAllPoints()
        rootFrame:SetPoint(point, UIParent, relPoint or point, x, y)
    end
end
local function LoadPos()
    local p = db and db.profile; local pos = p and p.unlockPos
    if not pos then return nil end
    return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
end
local function ClearPos()
    local p = db and db.profile; if not p then return end
    p.unlockPos = nil
end
function ApplyPos()
    local p = db and db.profile; local pos = p and p.unlockPos
    if not pos or not rootFrame then return end
    rootFrame:ClearAllPoints()
    rootFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
end

function RegisterUnlockElements()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement
    EllesmereUI:RegisterUnlockElements({
        MK({
            key   = "EDR_Cluster",
            label = "Dragon Riding",
            group = "Dragon Riding",
            order = 700,
            getFrame = function() return rootFrame end,
            getSize  = function()
                local p = db.profile
                local totalH   = p.secondWindHeight + p.gap + p.skyridingHeight + p.gap + p.speedHeight
                local iconSize = totalH
                local totalW   = p.width + p.gap + iconSize
                return totalW, totalH
            end,
            setWidth = function(_, w)
                -- The unlock system reports the cluster's TOTAL width (via
                -- getSize), which equals speed-bar width + gap + icon size.
                -- Reverse-compute the speed-bar width so the stored value is
                -- consistent with what getSize returns on re-read.
                local p = db.profile
                local totalH   = p.secondWindHeight + p.gap + p.skyridingHeight + p.gap + p.speedHeight
                local iconSize = totalH
                local speedBarW = w - p.gap - iconSize
                p.width = max(60, floor(speedBarW + 0.5))
                Rebuild()
            end,
            setHeight = function() end,   -- height is derived, not directly settable
            savePos = SavePos, loadPos = LoadPos, clearPos = ClearPos, applyPos = ApplyPos,
        }),
    })
end

-- Exports for the options file and unlock system
-- Defined here (after Build/Rebuild/Redraw rebinds) so closures capture the real bodies.
_G._EDR_Rebuild = function() Rebuild() end
_G._EDR_Redraw  = function() Redraw()  end
_G._EDR_GetRoot = function() return rootFrame end
