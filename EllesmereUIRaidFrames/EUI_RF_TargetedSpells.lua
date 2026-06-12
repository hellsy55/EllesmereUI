local ADDON_NAME, ns = ...

local CreateFrame   = CreateFrame
local C_Timer       = C_Timer
local GetTime       = GetTime
local UnitExists    = UnitExists
local UnitClass     = UnitClass
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local UnitRace      = UnitRace
local UnitSex       = UnitSex
local tremove       = table.remove
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitCanAttack = UnitCanAttack
local IsInGroup     = IsInGroup
local IsInRaid      = IsInRaid
local pairs         = pairs
local ipairs        = ipairs
local type          = type
local wipe          = wipe
local lower         = string.lower
local random        = math.random
local issecret      = issecretvalue or function() return false end

local ROSTER_UNITS = { "player", "party1", "party2", "party3", "party4" }
local T1 = 0.1
local T2 = 0.15
local T3 = 0.05
local T4 = 20
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function S()
    return ns.db and ns.db.profile
end

local dA = {}
local dB  = {}
local dC  = {}
local dD   = {}

local function Sync()
    wipe(dA)
    wipe(dB)
    wipe(dC)
    wipe(dD)
    for _, u in ipairs(ROSTER_UNITS) do
        local ex = UnitExists(u)
        if not issecret(ex) and ex == true then
            local _, v1 = UnitClass(u)
            if not issecret(v1) and type(v1) == "string" then
                dA[u] = v1
            end
            local v2 = UnitGroupRolesAssigned(u)
            if not issecret(v2) and type(v2) == "string" and v2 ~= "NONE" then
                dB[u] = v2
            end
            local _, v3 = UnitRace(u)
            if not issecret(v3) and type(v3) == "string" then
                dC[u] = v3
            end
            local v4 = UnitSex(u)
            if not issecret(v4) and type(v4) == "number" then
                dD[u] = v4
            end
        end
    end
end

local buf = {}

local function Trim(val, m)
    if val == nil or #buf <= 1 then return end
    local exact = 0
    for i = 1, #buf do
        if m[buf[i]] == val then exact = exact + 1 end
    end
    if exact == 0 then return end
    for i = #buf, 1, -1 do
        if m[buf[i]] ~= val then
            tremove(buf, i)
        end
    end
end

local function Match(caster)
    local tgt = caster .. "target"
    local _, k1 = UnitClass(tgt)
    if issecret(k1) or type(k1) ~= "string" then return nil end

    wipe(buf)
    for _, u in ipairs(ROSTER_UNITS) do
        if dA[u] == k1 then buf[#buf + 1] = u end
    end
    if #buf == 0 then
        Sync()
        for _, u in ipairs(ROSTER_UNITS) do
            if dA[u] == k1 then buf[#buf + 1] = u end
        end
        if #buf == 0 then return nil end
    end

    local v2 = UnitGroupRolesAssigned(tgt)
    if issecret(v2) or v2 == "NONE" then v2 = nil end
    Trim(v2, dB)

    local okR, _, v3 = pcall(UnitRace, tgt)
    if not okR or issecret(v3) or type(v3) ~= "string" then v3 = nil end
    Trim(v3, dC)

    local okS, v4 = pcall(UnitSex, tgt)
    if not okS or issecret(v4) or type(v4) ~= "number" then v4 = nil end
    Trim(v4, dD)

    if #buf ~= 1 then return nil end
    return buf
end

local buttonIcons = setmetatable({}, { __mode = "k" })

local function StyleIcon(icon)
    local s = S()
    local sz = ((s and s.tsIconSize) or 24) * (ns._partyIndicatorScale or 1)
    icon:SetSize(sz, sz)
    if icon._borderFrame then
        local PP = EllesmereUI and (EllesmereUI.PanelPP or EllesmereUI.PP)
        if PP and PP.UpdateBorder then
            PP.UpdateBorder(icon._borderFrame, 1, 0, 0, 0, 1)
            icon._borderFrame:Show()
        end
    end
end

local function CreateIcon(btn)
    local icon = CreateFrame("Frame", nil, btn)
    icon:SetFrameLevel(btn:GetFrameLevel() + 12)
    icon:Hide()

    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon._tex = tex

    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetSwipeColor(0, 0, 0, 0.6)
    cd:SetReverse(true)
    cd:SetHideCountdownNumbers(true)
    icon._cooldown = cd

    local bdr = CreateFrame("Frame", nil, icon)
    bdr:SetAllPoints()
    bdr:SetFrameLevel(icon:GetFrameLevel() + 1)
    local PP = EllesmereUI and (EllesmereUI.PanelPP or EllesmereUI.PP)
    if PP and PP.CreateBorder then
        PP.CreateBorder(bdr, 0, 0, 0, 1, 1)
    end
    icon._borderFrame = bdr

    StyleIcon(icon)
    return icon
end

local function AcquireIcon(btn)
    local icons = buttonIcons[btn]
    if not icons then
        icons = {}
        buttonIcons[btn] = icons
    end
    local s = S()
    local maxIcons = (s and s.tsMaxIcons) or 3
    for i = 1, #icons do
        if not icons[i]._tsCaster then return icons[i] end
    end
    if #icons >= maxIcons then return nil end
    local icon = CreateIcon(btn)
    icons[#icons + 1] = icon
    return icon
end

local function Place(icon, host, pos, fx, fy)
    if pos == "topleft" then
        icon:SetPoint("TOPLEFT", host, "TOPLEFT", fx, fy)
    elseif pos == "top" then
        icon:SetPoint("TOP", host, "TOP", fx, fy)
    elseif pos == "topright" then
        icon:SetPoint("TOPRIGHT", host, "TOPRIGHT", fx, fy)
    elseif pos == "left" then
        icon:SetPoint("LEFT", host, "LEFT", fx, fy)
    elseif pos == "right" then
        icon:SetPoint("RIGHT", host, "RIGHT", fx, fy)
    elseif pos == "bottomleft" then
        icon:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", fx, fy)
    elseif pos == "bottom" then
        icon:SetPoint("BOTTOM", host, "BOTTOM", fx, fy)
    elseif pos == "bottomright" then
        icon:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", fx, fy)
    else
        icon:SetPoint("CENTER", host, "CENTER", fx, fy)
    end
end

local function LayoutButton(btn)
    local icons = buttonIcons[btn]
    if not icons then return end
    local s = S()
    local k = ns._partyIndicatorScale or 1
    local sz = ((s and s.tsIconSize) or 24) * k
    local pos = lower((s and s.tsPosition) or "center")
    local grow = (s and s.tsGrowDirection) or "CENTER"
    local ox = ((s and s.tsOffsetX) or 0) * k
    local oy = ((s and s.tsOffsetY) or 0) * k
    local anchor = btn._health or btn
    local spc = 2 * k
    local spacing = sz + spc

    local shown = 0
    for i = 1, #icons do
        if icons[i]._tsCaster then shown = shown + 1 end
    end
    if shown == 0 then return end

    local centerOff = 0
    if grow == "CENTER" and shown > 0 then
        centerOff = -((shown - 1) * spacing) / 2
    end

    local prev
    for i = 1, #icons do
        local icon = icons[i]
        if icon._tsCaster then
            icon:ClearAllPoints()
            if not prev then
                Place(icon, anchor, pos, ox + (grow == "CENTER" and centerOff or 0), oy)
            else
                if grow == "RIGHT" or grow == "CENTER" then
                    icon:SetPoint("LEFT", prev, "RIGHT", spc, 0)
                elseif grow == "LEFT" then
                    icon:SetPoint("RIGHT", prev, "LEFT", -spc, 0)
                elseif grow == "UP" then
                    icon:SetPoint("BOTTOM", prev, "TOP", 0, spc)
                else
                    icon:SetPoint("TOP", prev, "BOTTOM", 0, -spc)
                end
            end
            prev = icon
        end
    end
end

local gen = {}
local activeIcons = {}
local tracked = {}

local function ClearCaster(caster)
    gen[caster] = (gen[caster] or 0) + 1
    tracked[caster] = nil
    local icons = activeIcons[caster]
    if not icons then return end
    activeIcons[caster] = nil
    local touched = {}
    for i = 1, #icons do
        local icon = icons[i]
        icon._tsCaster = nil
        icon:Hide()
        if icon._cooldown then
            icon._cooldown:Clear()
            icon._cooldown:Hide()
        end
        touched[icon:GetParent()] = true
    end
    for btn in pairs(touched) do LayoutButton(btn) end
end

local function ClearAll()
    for caster in pairs(activeIcons) do ClearCaster(caster) end
    wipe(tracked)
end

local function ShowFor(caster, matches, texture, durObj)
    local map = ns._partyUnitToButton
    if not map then return end
    local shownAny = false
    local list
    for _, unitToken in ipairs(matches) do
        local btn = map[unitToken]
        if btn and btn:IsShown() then
            local icon = AcquireIcon(btn)
            if icon then
                icon._tsCaster = caster
                StyleIcon(icon)
                if type(texture) == "nil" then
                    icon._tex:SetTexture(FALLBACK_ICON)
                else
                    icon._tex:SetTexture(texture)
                end
                local cd = icon._cooldown
                if durObj and cd.SetCooldownFromDurationObject then
                    cd:SetCooldownFromDurationObject(durObj)
                    if durObj.IsZero and cd.SetAlphaFromBoolean then
                        cd:SetAlphaFromBoolean(durObj:IsZero(), 0, 1)
                    else
                        cd:SetAlpha(1)
                    end
                    cd:SetDrawSwipe(true)
                    cd:Show()
                else
                    cd:Clear()
                    cd:Hide()
                end
                icon:Show()
                LayoutButton(btn)
                shownAny = true
                if not list then list = {} end
                list[#list + 1] = icon
            end
        end
    end
    if shownAny then
        activeIcons[caster] = list
    end
end

local function Resolve(caster, myGen)
    if gen[caster] ~= myGen then return end
    local castName, _, texture = UnitCastingInfo(caster)
    local channeling = false
    if type(castName) == "nil" then
        castName, _, texture = UnitChannelInfo(caster)
        channeling = true
    end
    if type(castName) == "nil" then return end

    if UnitShouldDisplaySpellTargetName then
        local sd = UnitShouldDisplaySpellTargetName(caster)
        if not issecret(sd) and sd == false then return end
    end

    local matches = Match(caster)
    if not matches then return end

    local newKey = table.concat(matches, ",")
    local icons = activeIcons[caster]
    if icons and icons.key == newKey then return end

    local durObj
    if channeling then
        durObj = UnitChannelDuration and UnitChannelDuration(caster)
    else
        durObj = UnitCastingDuration and UnitCastingDuration(caster)
    end

    if icons then
        activeIcons[caster] = nil
        local touched = {}
        for i = 1, #icons do
            icons[i]._tsCaster = nil
            icons[i]:Hide()
            touched[icons[i]:GetParent()] = true
        end
        for btn in pairs(touched) do LayoutButton(btn) end
    end

    ShowFor(caster, matches, texture, durObj)
    local list = activeIcons[caster]
    if list then list.key = newKey end

    C_Timer.After(T4, function()
        if gen[caster] == myGen then ClearCaster(caster) end
    end)
end

local function OnCastStart(caster)
    ClearCaster(caster)
    local hostile = UnitCanAttack("player", caster)
    if not issecret(hostile) and hostile ~= true then return end
    if UnitShouldDisplaySpellTargetName then
        local sd = UnitShouldDisplaySpellTargetName(caster)
        if not issecret(sd) and sd == false then return end
    end
    tracked[caster] = true
    local myGen = gen[caster]
    C_Timer.After(T1, function() Resolve(caster, myGen) end)
    C_Timer.After(T1 + T2, function() Resolve(caster, myGen) end)
end

local function OnRetarget(caster)
    if not tracked[caster] then return end
    gen[caster] = (gen[caster] or 0) + 1
    local myGen = gen[caster]
    C_Timer.After(T3, function() Resolve(caster, myGen) end)
    C_Timer.After(T3 + T2, function() Resolve(caster, myGen) end)
end

local ev = CreateFrame("Frame")
local castEventsOn = false

local CAST_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_TARGET",
    "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
}

local function ShouldBeActive()
    local s = S()
    if not s or s.tsEnabled == false then return false end
    return IsInGroup() and not IsInRaid()
end

local function UpdateActive()
    local want = ShouldBeActive()
    if want and not castEventsOn then
        for _, e in ipairs(CAST_EVENTS) do ev:RegisterEvent(e) end
        castEventsOn = true
        Sync()
    elseif not want and castEventsOn then
        for _, e in ipairs(CAST_EVENTS) do ev:UnregisterEvent(e) end
        castEventsOn = false
        ClearAll()
    end
end

ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_ROLES_ASSIGNED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        UpdateActive()
        return
    end
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
        Sync()
        ClearAll()
        UpdateActive()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        ClearAll()
        UpdateActive()
        return
    end
    if type(unit) ~= "string" or not unit:match("^nameplate%d+$") then return end
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        OnCastStart(unit)
    elseif event == "UNIT_TARGET" then
        OnRetarget(unit)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local castName = UnitCastingInfo(unit)
        if type(castName) == "nil" then
            castName = UnitChannelInfo(unit)
        end
        if type(castName) ~= "nil" then
            OnCastStart(unit)
        end
    else
        ClearCaster(unit)
    end
end)

local pvIcons = {}
local pvTicker
local PV_HOSTS = { 2, 3 }
local PV_TEX = { 135807, 136197 }

local function StopPvTicker()
    if pvTicker then
        pvTicker:Cancel()
        pvTicker = nil
    end
end

local function PvTick()
    if not ns._partyPvActive then
        StopPvTicker()
        return
    end
    local now = GetTime()
    for i = 1, #pvIcons do
        local icon = pvIcons[i]
        if icon and icon._tsCaster and icon._cooldown then
            if not icon._pvExp or icon._pvExp <= now then
                local dur = random(4, 12)
                icon._pvExp = now + dur
                icon._cooldown:SetCooldown(now, dur)
                icon._cooldown:Show()
            end
        end
    end
end

function ns.TS_RefreshPreview()
    local s = S()
    local frames = ns._partyPvFrames
    local on = ns._partyPvActive and frames and ns._tsPreviewVisible
        and s and s.tsEnabled ~= false
    if not on then
        StopPvTicker()
        for i = 1, #pvIcons do
            pvIcons[i]._tsCaster = nil
            pvIcons[i]._pvExp = nil
            pvIcons[i]:Hide()
        end
        return
    end
    local k = ns._partyIndicatorScale or 1
    local pos = lower((s and s.tsPosition) or "center")
    local ox = ((s and s.tsOffsetX) or 0) * k
    local oy = ((s and s.tsOffsetY) or 0) * k
    for i = 1, #PV_HOSTS do
        local host = frames[PV_HOSTS[i]]
        local icon = pvIcons[i]
        if host then
            if not icon or icon:GetParent() ~= host then
                if icon then icon:Hide() end
                icon = CreateIcon(host)
                pvIcons[i] = icon
            end
            icon._tsCaster = "preview"
            StyleIcon(icon)
            icon._tex:SetTexture(PV_TEX[i])
            icon:ClearAllPoints()
            Place(icon, host._health or host, pos, ox, oy)
            icon._pvExp = nil
            icon:Show()
        elseif icon then
            icon._tsCaster = nil
            icon._pvExp = nil
            icon:Hide()
        end
    end
    PvTick()
    if not pvTicker then
        pvTicker = C_Timer.NewTicker(0.5, PvTick)
    end
end

function ns.TS_ApplySettings()
    UpdateActive()
    for btn, icons in pairs(buttonIcons) do
        local any = false
        for i = 1, #icons do
            if icons[i]._tsCaster then
                StyleIcon(icons[i])
                any = true
            end
        end
        if any then LayoutButton(btn) end
    end
    ns.TS_RefreshPreview()
end
