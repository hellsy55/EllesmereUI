-------------------------------------------------------------------------------
--  EllesmereUICdmHooks.lua  (v4 -- Simplified Event-Driven Architecture)
--
--  CORE PRINCIPLE: Blizzard manages all cooldown/buff state.
--  We ONLY restyle (borders, shapes, fonts) and reposition (into our bars).
--
--  Reanchor triggers (exhaustive list):
--    - Login/reload (C_Timer.After 0.2)
--    - BuffIconCooldownViewer.RefreshLayout (buff frames come/go)
--    - Explicit ns.QueueReanchor() from our code:
--        spec swap, talent change, zone in/out,
--        user edits Blizzard CDM, user edits EUI settings
--
--  NO hooks on: Layout, RefreshLayout, OnCooldownIDSet,
--  OnActiveStateChanged, itemFramePool Acquire/ReleaseAll.
--  These are Blizzard internal transitions, not our business.
-------------------------------------------------------------------------------
local _, ns = ...

-- Upvalue aliases (populated by EllesmereUICooldownManager.lua before this loads)
local ECME                   = ns.ECME
local barDataByKey           = ns.barDataByKey
local cdmBarFrames           = ns.cdmBarFrames
local cdmBarIcons            = ns.cdmBarIcons
local MAIN_BAR_KEYS          = ns.MAIN_BAR_KEYS
local ResolveInfoSpellID     = ns.ResolveInfoSpellID
local GetCDMFont             = ns.GetCDMFont

-- Per-frame decoration state (weak-keyed: auto-cleans when frame is GCed)
local hookFrameData = setmetatable({}, { __mode = "k" })
ns._hookFrameData = hookFrameData

-- External frame cache: avoid writing custom keys to Blizzard's secure frame
-- tables (which taints them and causes "secret value" errors).
local _ecmeFC = ns._ecmeFC
local FC = ns.FC

-- Convenience: get or create hookFrameData entry for a frame
local function FD(f) local d = hookFrameData[f]; if not d then d = {}; hookFrameData[f] = d end; return d end
ns.FD = FD

-- Spell routing: spellID -> barKey. Rebuilt when bar config changes.
local _spellRouteMap = {}

-- Reusable scratch tables (wiped each CollectAndReanchor call)
local _scratch_barLists = {}
local _scratch_seenSpell = {}
local _scratch_spellOrder = {}
local _scratch_allowSet = {}
local _scratch_filtered = {}
local _scratch_usedFrames = {}

-- Entry pool: reuse entry tables across ticks to avoid garbage
local _entryPool = {}
local _entryPoolSize = 0
local function AcquireEntry(frame, spellID, baseSpellID, layoutIndex)
    local e
    if _entryPoolSize > 0 then
        e = _entryPool[_entryPoolSize]
        _entryPool[_entryPoolSize] = nil
        _entryPoolSize = _entryPoolSize - 1
    else
        e = {}
    end
    e.frame = frame
    e.spellID = spellID
    e.baseSpellID = baseSpellID
    e.layoutIndex = layoutIndex
    e._inactive = nil
    return e
end
local function ReleaseEntries(list)
    for i = 1, #list do
        local e = list[i]
        if e then
            e.frame = nil
            _entryPoolSize = _entryPoolSize + 1
            _entryPool[_entryPoolSize] = e
        end
        list[i] = nil
    end
end

-------------------------------------------------------------------------------
--  Preset Buff Frames
--  Self-contained system for tracking external buffs (Bloodlust, potions, etc.)
--  that don't exist in Blizzard's CDM viewer pool.
-------------------------------------------------------------------------------
local _presetFrames = {}  -- [barKey..":"..primarySpellID] = frame
ns._presetFrames = _presetFrames

-- Racial cooldown event listener: marks racial frames dirty on cooldown
-- change so the next reanchor refreshes their DurationObject.
local _racialCdListener = CreateFrame("Frame")
_racialCdListener:RegisterEvent("SPELL_UPDATE_COOLDOWN")
_racialCdListener:RegisterEvent("SPELL_UPDATE_CHARGES")
_racialCdListener:SetScript("OnEvent", function()
    for _, f in pairs(_presetFrames) do
        if f._isRacialFrame then f._racialCdDirty = true end
    end
    if QueueCustomBuffUpdate then QueueCustomBuffUpdate() end
end)

-- UNIT_SPELLCAST_SUCCEEDED: fires the EXACT spell ID that was cast.
-- Used by Custom Aura Bars to detect which specific spell was used
-- (potions share cooldowns, so SPELL_UPDATE_COOLDOWN can't distinguish).
-- Works in combat. Accumulates cast IDs into a set for batched processing.
local _pendingCastIDs = {}
local _customBuffDirty = false
local _customBuffFrame = CreateFrame("Frame")
_customBuffFrame:Hide()
local CUSTOM_BUFF_THROTTLE = 0.05
local _lastCustomBuffTime = 0
_customBuffFrame:SetScript("OnUpdate", function(self)
    if not _customBuffDirty then self:Hide(); return end
    local now = GetTime()
    if now - _lastCustomBuffTime < CUSTOM_BUFF_THROTTLE then return end
    _customBuffDirty = false
    _lastCustomBuffTime = now
    if ns.UpdateCustomBuffBars then ns.UpdateCustomBuffBars() end
end)

local function QueueCustomBuffUpdate()
    _customBuffDirty = true
    _customBuffFrame:Show()
end

local _spellCastListener = CreateFrame("Frame")
_spellCastListener:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
_spellCastListener:SetScript("OnEvent", function(_, _, _, _, spellID)
    if spellID then
        _pendingCastIDs[spellID] = true
        QueueCustomBuffUpdate()
    end
end)

-- (Preset buff frame system removed — presets are no longer injected.
-- _presetFrames table is still used for racial frame caching.)

-------------------------------------------------------------------------------
--  Trinket Frames
--  Custom frames for equipped on-use trinkets (slot 13/14).
-------------------------------------------------------------------------------
local _trinketFrames = {}
local _trinketItemCache = { [13] = nil, [14] = nil }

local function GetOrCreateTrinketFrame(slotID)
    local f = _trinketFrames[slotID]
    if f then return f end

    f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(36, 36)
    f:Hide()

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.Icon = tex
    f._tex = tex

    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(true)
    f.Cooldown = cd
    f._cooldown = cd

    f._isTrinketFrame = true
    f._trinketSlot = slotID
    f.cooldownID = nil
    f.cooldownInfo = nil
    f.layoutIndex = slotID == 13 and 99990 or 99991
    f.isActive = false
    f.auraInstanceID = nil
    f.cooldownDuration = 0

    _trinketFrames[slotID] = f
    return f
end

local function UpdateTrinketFrame(slotID)
    local f = _trinketFrames[slotID]
    if not f then return end
    local itemID = GetInventoryItemID("player", slotID)
    _trinketItemCache[slotID] = itemID
    if not itemID then
        f:Hide()
        return
    end
    local icon = C_Item.GetItemIconByID(itemID)
    if icon and f._tex then f._tex:SetTexture(icon) end
    local _, spellID = C_Item.GetItemSpell(itemID)
    f._trinketSpellID = spellID
    local isRealOnUse = false
    if spellID and spellID > 0 then
        local tipData = C_TooltipInfo and C_TooltipInfo.GetItemByID(itemID)
        if tipData and tipData.lines then
            for _, tipLine in ipairs(tipData.lines) do
                local lt = tipLine.leftText
                if lt and lt:find("Cooldown%)") then
                    local cdStr = lt:match("%((.+Cooldown)%)")
                    if cdStr then
                        local totalSec = 0
                        for num, unit in cdStr:gmatch("(%d+)%s*(%a+)") do
                            local n = tonumber(num)
                            if n then
                                local u = unit:lower()
                                if u == "min" then totalSec = totalSec + n * 60
                                elseif u == "sec" then totalSec = totalSec + n
                                elseif u == "hr" or u == "hour" then totalSec = totalSec + n * 3600
                                end
                            end
                        end
                        if totalSec >= 20 then isRealOnUse = true end
                    end
                end
            end
        end
    end
    f._trinketIsOnUse = isRealOnUse
end

local function UpdateTrinketCooldown(slotID)
    local f = _trinketFrames[slotID]
    if not f or not f._trinketIsOnUse then return false end
    local start, dur, enable = GetInventoryItemCooldown("player", slotID)
    if start and dur and dur > 1.5 and enable == 1 then
        f._cooldown:SetCooldown(start, dur)
        return true
    else
        f._cooldown:Clear()
        return false
    end
end

-- Event frame for trinket updates
local _trinketEventFrame = CreateFrame("Frame")
_trinketEventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
_trinketEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
_trinketEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
_trinketEventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        if arg1 == 13 or arg1 == 14 then
            UpdateTrinketFrame(arg1)
            if ns.QueueReanchor then ns.QueueReanchor() end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateTrinketFrame(13)
        UpdateTrinketFrame(14)
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        -- Update trinket cooldown displays (no reanchor needed —
        -- the frame's own Cooldown widget handles the visual)
        for _, slot in ipairs({13, 14}) do
            if _trinketFrames[slot] and _trinketFrames[slot]._trinketIsOnUse then
                UpdateTrinketCooldown(slot)
            end
        end
    end
end)

-- Sort comparator (hoisted to avoid closure creation per call)
local function _sortBySpellOrder(a, b)
    local ai = _scratch_spellOrder[a.baseSpellID] or _scratch_spellOrder[a.spellID] or 10000
    local bi = _scratch_spellOrder[b.baseSpellID] or _scratch_spellOrder[b.spellID] or 10000
    if ai ~= bi then return ai < bi end
    return a.layoutIndex < b.layoutIndex
end

-- Reanchor queue state
local reanchorDirty = false
local reanchorFrame = nil
local viewerHooksInstalled = false

-- Maps Blizzard viewer name <-> our bar key
local HOOK_VIEWER_TO_BAR = {
    EssentialCooldownViewer = "cooldowns",
    UtilityCooldownViewer   = "utility",
    BuffIconCooldownViewer  = "buffs",
}
local HOOK_BAR_TO_VIEWER = {}
for vn, bk in pairs(HOOK_VIEWER_TO_BAR) do HOOK_BAR_TO_VIEWER[bk] = vn end

--- Resolve spellID from a Blizzard CDM pool frame.
-- Uses cached result from FC; invalidated when cooldownID changes.
local function ResolveFrameSpellID(frame)
    local cdID = frame.cooldownID
    if not cdID and frame.cooldownInfo then
        cdID = frame.cooldownInfo.cooldownID
    end
    if not cdID or not C_CooldownViewer then return nil, nil end

    local fc = _ecmeFC[frame]
    -- Check cache validity
    if fc and fc.resolvedSid and fc.cachedCdID == cdID then
        -- Refresh live override (lightweight API, no table alloc)
        local baseSID = fc.baseSpellID
        if baseSID and C_SpellBook and C_SpellBook.FindSpellOverrideByID then
            local liveOvr = C_SpellBook.FindSpellOverrideByID(baseSID)
            if liveOvr and liveOvr ~= 0 and liveOvr ~= fc.overrideSid then
                fc.overrideSid = liveOvr
                fc.resolvedSid = liveOvr
            end
        end
        return fc.resolvedSid, fc.baseSpellID
    end

    -- Cache miss: resolve from API
    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
    if not info then return nil, nil end
    local displaySID = ResolveInfoSpellID(info)
    if not displaySID or displaySID <= 0 then return nil, nil end
    local baseSID = info.spellID
    if not baseSID or baseSID <= 0 then baseSID = displaySID end

    if not fc then fc = {}; _ecmeFC[frame] = fc end
    fc.resolvedSid = displaySID
    fc.baseSpellID = baseSID
    fc.overrideSid = info.overrideSpellID
    fc.cachedCdID = cdID
    fc.cachedAuraInstID = frame.auraInstanceID

    -- Cache linkedSpellIDs for spells like Eclipse
    if info.linkedSpellIDs and #info.linkedSpellIDs > 0 then
        fc.linkedSpellIDs = info.linkedSpellIDs
    else
        fc.linkedSpellIDs = nil
    end

    return displaySID, baseSID
end
ns.ResolveFrameSpellID = ResolveFrameSpellID

-------------------------------------------------------------------------------
--  HideBlizzardDecorations
--  Strips Blizzard's visual chrome from a CDM pool frame (one-time per frame).
-------------------------------------------------------------------------------
local function HideBlizzardDecorations(frame)
    local fc = FC(frame)
    if fc.blizzHidden then return end
    fc.blizzHidden = true

    local function alphaOnly(child)
        if child then child:SetAlpha(0) end
    end
    alphaOnly(frame.Border)
    alphaOnly(frame.SpellActivationAlert)
    alphaOnly(frame.Shadow)
    alphaOnly(frame.IconShadow)
    alphaOnly(frame.DebuffBorder)
    alphaOnly(frame.CooldownFlash)

    -- Neutralize circular mask
    local iconWidget = frame.Icon
    local regions = { frame:GetRegions() }
    for ri = 1, #regions do
        local rgn = regions[ri]
        if rgn and rgn.IsObjectType and rgn:IsObjectType("MaskTexture") then
            pcall(function() rgn:SetTexture("Interface\\Buttons\\WHITE8X8") end)
        end
    end
    if frame.Cooldown then
        local cdRegions = { frame.Cooldown:GetRegions() }
        for ri = 1, #cdRegions do
            local rgn = cdRegions[ri]
            if rgn and rgn.IsObjectType and rgn:IsObjectType("MaskTexture") then
                pcall(function() rgn:SetTexture("Interface\\Buttons\\WHITE8X8") end)
            end
        end
    end

    -- Hide known Blizzard overlay textures
    local OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
    local OVERLAY_FILE  = 6707800
    for ri = 1, #regions do
        local rgn = regions[ri]
        if rgn and rgn ~= iconWidget and rgn.IsObjectType and rgn:IsObjectType("Texture") then
            local atlas = rgn.GetAtlas and rgn:GetAtlas()
            local tex = rgn.GetTexture and rgn:GetTexture()
            if atlas == OVERLAY_ATLAS or tex == OVERLAY_FILE then
                rgn:SetAlpha(0)
                rgn:Hide()
            end
        end
    end

    if frame.Cooldown then
        frame.Cooldown:SetHideCountdownNumbers(true)
    end
end

-------------------------------------------------------------------------------
--  DecorateFrame
--  Add our visual overlays to a Blizzard CDM frame (one-time per frame).
-------------------------------------------------------------------------------
local function DecorateFrame(frame, barData)
    local fd = hookFrameData[frame]
    if fd and fd.decorated then return fd end
    if not fd then fd = {}; hookFrameData[frame] = fd end
    fd.decorated = true

    local iconWidget = frame.Icon
    if iconWidget and not iconWidget.GetTexture then
        if iconWidget.Icon then iconWidget = iconWidget.Icon end
    end
    fd.tex = iconWidget
    fd.cooldown = frame.Cooldown

    frame:SetScale(1)
    HideBlizzardDecorations(frame)

    -- Background
    if not fd.bg then
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(barData.bgR or 0.08, barData.bgG or 0.08,
            barData.bgB or 0.08, barData.bgA or 0.6)
        fd.bg = bg
    end

    -- Glow overlay
    if not fd.glowOverlay then
        local go = CreateFrame("Frame", nil, frame)
        go:SetAllPoints(frame)
        go:SetFrameLevel(frame:GetFrameLevel() + 2)
        go:SetAlpha(0)
        go:EnableMouse(false)
        fd.glowOverlay = go
    end

    -- Text overlay
    if not fd.textOverlay then
        local txo = CreateFrame("Frame", nil, frame)
        txo:SetAllPoints(frame)
        txo:SetFrameLevel(frame:GetFrameLevel() + 3)
        txo:EnableMouse(false)
        fd.textOverlay = txo
    end

    -- Keybind text
    if not fd.keybindText then
        local kt = fd.textOverlay:CreateFontString(nil, "OVERLAY")
        kt:SetFont(GetCDMFont(), barData.keybindSize or 10, "OUTLINE")
        kt:SetShadowOffset(0, 0)
        kt:SetPoint("TOPLEFT", fd.textOverlay, "TOPLEFT",
            barData.keybindOffsetX or 2, barData.keybindOffsetY or -2)
        kt:SetJustifyH("LEFT")
        kt:SetTextColor(barData.keybindR or 1, barData.keybindG or 1,
            barData.keybindB or 1, barData.keybindA or 0.9)
        kt:Hide()
        fd.keybindText = kt
    end

    fd.tooltipShown = false

    -- Suppress Blizzard's built-in tooltip when showTooltip is off.
    local fc = FC(frame)
    if not fc.tooltipHooked then
        fc.tooltipHooked = true
        frame:HookScript("OnEnter", function()
            local ffc = _ecmeFC[frame]
            local bd = ffc and ffc.barKey and barDataByKey[ffc.barKey]
            if bd and not bd.showTooltip then
                GameTooltip:Hide()
            end
        end)
    end

    -- PP border on a dedicated child frame (avoids tainting Blizzard frames)
    if not fd.borderFrame then
        local bf = CreateFrame("Frame", nil, frame)
        bf:SetAllPoints(frame)
        bf:SetFrameLevel(frame:GetFrameLevel())
        fd.borderFrame = bf
        EllesmereUI.PP.CreateBorder(bf,
            barData.borderR or 0, barData.borderG or 0,
            barData.borderB or 0, barData.borderA or 1,
            barData.borderSize or 1, "OVERLAY", 7)
    end

    fd.isActive = false
    fd.procGlowActive = false

    -- Cooldown widget styling
    if fd.cooldown then
        fd.cooldown:SetDrawEdge(false)
        fd.cooldown:SetDrawSwipe(true)
        fd.cooldown:SetDrawBling(false)
        fd.cooldown:SetSwipeColor(0, 0, 0, barData.swipeAlpha or 0.7)
        fd.cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
        fd.cooldown:SetHideCountdownNumbers(not barData.showCooldownText)
        local isBuff = (barData.barType == "buffs" or barData.key == "buffs" or barData.barType == "custom_buff")
        fd.cooldown:SetReverse(isBuff)
    end

    hookFrameData[frame] = fd
    return fd
end

-- (IsBuffActive removed — hideInactive uses auraInstanceID == nil directly)

-------------------------------------------------------------------------------
--  CategorizeFrame
--  Resolve which bar a viewer frame belongs to.
-------------------------------------------------------------------------------
local function CategorizeFrame(frame, viewerBarKey)
    local displaySID, baseSID = ResolveFrameSpellID(frame)
    if not displaySID or displaySID <= 0 then return nil, nil, nil end

    -- Check if any bar claims this spell (cross-viewer routing)
    local claimBarKey = _spellRouteMap[baseSID] or _spellRouteMap[displaySID]
    if claimBarKey then
        local claimBD = barDataByKey[claimBarKey]
        local claimType = claimBD and claimBD.barType or claimBarKey
        local viewerIsBuff = (viewerBarKey == "buffs")
        local claimIsBuff = (claimType == "buffs")
        if viewerIsBuff == claimIsBuff then
            return claimBarKey, displaySID, baseSID
        end
    end
    return viewerBarKey, displaySID, baseSID
end

-------------------------------------------------------------------------------
--  RebuildSpellRouteMap
-------------------------------------------------------------------------------
function ns.RebuildSpellRouteMap()
    wipe(_spellRouteMap)
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars then return end
    local _FindOverride = C_SpellBook and C_SpellBook.FindSpellOverrideByID
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled then
            local sd = ns.GetBarSpellData(bd.key)
            if sd and sd.assignedSpells then
                for _, sid in ipairs(sd.assignedSpells) do
                    if type(sid) == "number" and sid > 0 then
                        _spellRouteMap[sid] = bd.key
                        if _FindOverride then
                            local ovr = _FindOverride(sid)
                            if ovr and ovr > 0 and ovr ~= sid then
                                _spellRouteMap[ovr] = bd.key
                            end
                        end
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Side-effect caches (built once per reanchor, stable between reanchors)
--  These replace the old per-tick caches from UpdateAllCDMBars.
-------------------------------------------------------------------------------
local _activeCache      = {}   -- [spellID] = true when buff/aura is active
local _barViewerCache   = {}   -- [spellID] = blizzChild (BuffBarCooldownViewer)
local _cdUtilTrackedSet = {}   -- [spellID] = true (in CD/Utility viewer)
local _buffIconTrackedSet = {} -- [spellID] = true (in BuffIcon viewer)
local _allChildCache    = {}   -- [spellID] = blizzChild (any viewer)
local _buffChildCache   = {}   -- [spellID] = blizzChild (buff viewers)

-- Expose for BarGlows, BuffBars, SpellPicker, Options
ns._tickBlizzActiveCache    = _activeCache
ns._tickBarViewerCache      = _barViewerCache
ns._tickCDUtilTrackedSet    = _cdUtilTrackedSet
ns._tickBuffIconTrackedSet  = _buffIconTrackedSet
ns._tickBlizzAllChildCache  = _allChildCache
ns._tickBlizzBuffChildCache = _buffChildCache

-- Viewer name list for iteration
local _cdmViewerNames = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

local function RebuildSideEffectCaches()
    wipe(_activeCache)
    wipe(_barViewerCache)
    wipe(_cdUtilTrackedSet)
    wipe(_buffIconTrackedSet)
    wipe(_allChildCache)
    wipe(_buffChildCache)

    for vi = 1, 4 do
        local vName = _cdmViewerNames[vi]
        local vf = _G[vName]
        local isBuffViewer = (vi == 3 or vi == 4)
        local isBuffIconViewer = (vi == 3)
        if vf and vf.itemFramePool and vf.itemFramePool.EnumerateActive then
            for frame in vf.itemFramePool:EnumerateActive() do
                local displaySID, baseSID = ResolveFrameSpellID(frame)
                if displaySID and displaySID > 0 then
                    _allChildCache[displaySID] = frame
                    if baseSID and baseSID > 0 and baseSID ~= displaySID then
                        _allChildCache[baseSID] = frame
                    end

                    if isBuffViewer then
                        if isBuffIconViewer or not _buffChildCache[displaySID] then
                            _buffChildCache[displaySID] = frame
                        end
                        if not isBuffIconViewer then
                            _barViewerCache[displaySID] = frame
                            if baseSID and baseSID > 0 then
                                _barViewerCache[baseSID] = frame
                            end
                        end
                        if isBuffIconViewer then
                            _buffIconTrackedSet[displaySID] = true
                            if baseSID and baseSID > 0 then
                                _buffIconTrackedSet[baseSID] = true
                            end
                        end
                        -- Linked spells (Eclipse, etc.)
                        local fc = _ecmeFC[frame]
                        local linked = fc and fc.linkedSpellIDs
                        if linked then
                            for li = 1, #linked do
                                local lsid = linked[li]
                                if lsid and lsid > 0 then
                                    _allChildCache[lsid] = frame
                                    if isBuffIconViewer or not _buffChildCache[lsid] then
                                        _buffChildCache[lsid] = frame
                                    end
                                    if isBuffIconViewer then
                                        _buffIconTrackedSet[lsid] = true
                                    end
                                    if not isBuffIconViewer then
                                        _barViewerCache[lsid] = frame
                                    end
                                end
                            end
                        end
                    else
                        _cdUtilTrackedSet[displaySID] = true
                        if baseSID and baseSID > 0 then
                            _cdUtilTrackedSet[baseSID] = true
                        end
                    end

                    -- Active state: frame has aura data
                    if frame.wasSetFromAura == true or frame.auraInstanceID ~= nil then
                        _activeCache[displaySID] = true
                        if baseSID and baseSID > 0 then
                            _activeCache[baseSID] = true
                        end
                        local fc2 = _ecmeFC[frame]
                        local linked2 = fc2 and fc2.linkedSpellIDs
                        if linked2 then
                            for li = 1, #linked2 do
                                local lsid = linked2[li]
                                if lsid and lsid > 0 then
                                    _activeCache[lsid] = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  CollectAndReanchor (core layout function)
--  Called ONLY when hooks fire (not on a tick loop).
--
--  Principle: Blizzard controls all frame state. We ONLY restyle and reposition.
--  1. Collect shown frames from Blizzard (skip IsShown=false)
--  2. Route each frame to the correct bar via spellRouteMap
--  3. Inject our own frames (trinkets, racials, presets) for non-viewer spells
--  4. Sort by assignedSpells order
--  5. Decorate and position into our bar grid
--  6. Move unclaimed frames offscreen
-------------------------------------------------------------------------------
local function CollectAndReanchor()
    -- Suspend all hook logic while Blizzard CDM settings is open to prevent taint
    if CooldownViewerSettings and CooldownViewerSettings:IsShown() then return end

    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars or not p.cdmBars.enabled then return end

    RebuildSideEffectCaches()

    -- 1. Collect shown frames from all viewers
    local barLists = _scratch_barLists
    local seenSpell = _scratch_seenSpell
    for k, list in pairs(barLists) do ReleaseEntries(list) end
    for k, sub in pairs(seenSpell) do wipe(sub) end
    wipe(_scratch_usedFrames)
    local allActiveFrames = {}


    for viewerName, defaultBarKey in pairs(HOOK_VIEWER_TO_BAR) do
        local viewer = _G[viewerName]
        if not viewer then break end
        local isBuff = (viewerName == "BuffIconCooldownViewer")

        if isBuff then
            -- BUFF ICONS: use GetChildren() + IsShown() (CMC approach).
            -- Blizzard controls show/hide — we only collect what's visible.
            -- Hook per-frame aura events for re-layout detection.
            local children = { viewer:GetChildren() }
            for _, frame in ipairs(children) do
                if frame and (frame.Icon or frame.icon) and frame.layoutIndex ~= nil then
                    allActiveFrames[frame] = true
                    -- Hook aura events on each child (once) for re-layout
                    if not frame._euiBuffHooked then
                        frame._euiBuffHooked = true
                        local function BuffChanged() if ns.QueueReanchor then ns.QueueReanchor() end end
                        if frame.OnActiveStateChanged then hooksecurefunc(frame, "OnActiveStateChanged", BuffChanged) end
                        if frame.OnUnitAuraAddedEvent then hooksecurefunc(frame, "OnUnitAuraAddedEvent", BuffChanged) end
                        if frame.OnUnitAuraRemovedEvent then hooksecurefunc(frame, "OnUnitAuraRemovedEvent", BuffChanged) end
                    end
                    if frame:IsShown() then
                        local targetBar, displaySID, baseSID = CategorizeFrame(frame, defaultBarKey)
                        if targetBar and displaySID and displaySID > 0 then
                            local barSeen = seenSpell[targetBar]
                            if not barSeen then barSeen = {}; seenSpell[targetBar] = barSeen end
                            if not barSeen[displaySID] then
                                if not barLists[targetBar] then barLists[targetBar] = {} end
                                local entry = AcquireEntry(frame, displaySID, baseSID or displaySID, frame.layoutIndex or 0)
                                barLists[targetBar][#barLists[targetBar] + 1] = entry
                                barSeen[displaySID] = entry
                            end
                        end
                    end
                end
            end
        elseif viewer.itemFramePool then
            -- CD/UTILITY: use EnumerateActive() (stable, always in pool)
            for frame in viewer.itemFramePool:EnumerateActive() do
                allActiveFrames[frame] = true
                -- Skip untalented spells (grayed out in Blizzard CDM)
                local displaySID_pre = ResolveFrameSpellID(frame)
                local isUnknown = displaySID_pre and displaySID_pre > 0
                    and not ns.IsSpellKnownInCDM(displaySID_pre)
                if not isUnknown then
                    local targetBar, displaySID, baseSID = CategorizeFrame(frame, defaultBarKey)
                    if targetBar and displaySID and displaySID > 0 then
                        local barSeen = seenSpell[targetBar]
                        if not barSeen then barSeen = {}; seenSpell[targetBar] = barSeen end
                        if not barSeen[displaySID] then
                            if not barLists[targetBar] then barLists[targetBar] = {} end
                            local entry = AcquireEntry(frame, displaySID, baseSID or displaySID, frame.layoutIndex or 0)
                            barLists[targetBar][#barLists[targetBar] + 1] = entry
                            barSeen[displaySID] = entry
                        end
                    end
                end
            end
        end
    end

    local LayoutCDMBar = ns.LayoutCDMBar
    local RefreshCDMIconAppearance = ns.RefreshCDMIconAppearance
    local ApplyCDMTooltipState = ns.ApplyCDMTooltipState
    local _FindOverride = C_SpellBook and C_SpellBook.FindSpellOverrideByID

    -- Ensure bars with only non-viewer spells get processed.
    -- Custom Buff bars are entirely our own frames (not viewer-based),
    -- so they always need processing when they have spells.
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and not barLists[bd.key] then
            local sd = ns.GetBarSpellData(bd.key)
            if sd and sd.assignedSpells and #sd.assignedSpells > 0 then
                barLists[bd.key] = {}
            end
        end
    end

    -- 2-5. Process each bar (skip custom_buff — handled by UpdateCustomBuffBars)
    for barKey, list in pairs(barLists) do
        local barData = barDataByKey[barKey]
        if barData and barData.enabled and barData.barType ~= "custom_buff" then
            local container = cdmBarFrames[barKey]
            if container then
                local barHidden = container._visHidden
                local sd = ns.GetBarSpellData(barKey)
                local spellList = sd and sd.assignedSpells
                local barType = barData.barType or barKey

                -- Build spell order for sorting
                local spellOrder = _scratch_spellOrder; wipe(spellOrder)
                if spellList then
                    local idx = 0
                    for _, sid in ipairs(spellList) do
                        if sid and sid ~= 0 then
                            idx = idx + 1
                            spellOrder[sid] = idx
                        end
                    end
                end

                -- Filter list by assignedSpells (if set)
                if spellList and #spellList > 0 then
                    local allowSet = _scratch_allowSet; wipe(allowSet)
                    for _, sid in ipairs(spellList) do
                        if sid and sid > 0 then
                            allowSet[sid] = true
                            if _FindOverride then
                                local ovr = _FindOverride(sid)
                                if ovr and ovr > 0 then allowSet[ovr] = true end
                            end
                        end
                    end
                    local filtered = _scratch_filtered; wipe(filtered)
                    for _, entry in ipairs(list) do
                        if allowSet[entry.spellID] or allowSet[entry.baseSpellID] then
                            filtered[#filtered + 1] = entry
                        end
                    end
                    list = filtered
                end

                -- Inject our own frames for non-viewer spells (trinkets, racials,
                -- potions/items, custom spell IDs, custom buff tracking).
                -- Default "buffs" bar is excluded (Blizzard-driven).
                -- "custom_buff" bars are 100% our frames — every spell
                -- gets a frame, shown only when aura is active.
                local isCustomBuff = (barType == "custom_buff")
                if spellList and barType ~= "buffs" then
                    for _, sid in ipairs(spellList) do
                        if sid and sid == -13 or sid == -14 then
                            -- Trinket slots
                            local slot = -sid
                            local tf = _trinketFrames[slot]
                            if not tf then tf = GetOrCreateTrinketFrame(slot); UpdateTrinketFrame(slot) end
                            if _trinketItemCache[slot] and tf._trinketIsOnUse then
                                UpdateTrinketCooldown(slot)
                                DecorateFrame(tf, barData)
                                tf:Show()
                                list[#list + 1] = AcquireEntry(tf, sid, sid, spellOrder[sid] or 99999)
                            else
                                tf:Hide()
                            end
                        elseif sid and sid <= -100 then
                            -- Item preset (negated itemID: potions, healthstones, etc.)
                            local itemID = -sid
                            local fkey = barKey .. ":item:" .. itemID
                            local f = _presetFrames[fkey]
                            if not f then
                                local itemPresets = ns.CDM_ITEM_PRESETS
                                local preset
                                if itemPresets then
                                    for _, pr in ipairs(itemPresets) do
                                        if pr.itemID == itemID then preset = pr; break end
                                        if pr.altItemIDs then
                                            for _, alt in ipairs(pr.altItemIDs) do
                                                if alt == itemID then preset = pr; break end
                                            end
                                        end
                                    end
                                end
                                local icon = preset and preset.icon or C_Item.GetItemIconByID(itemID)
                                if icon then
                                    f = CreateFrame("Frame", nil, UIParent)
                                    f:SetSize(36, 36); f:Hide()
                                    local tex = f:CreateTexture(nil, "ARTWORK")
                                    tex:SetAllPoints(); tex:SetTexture(icon)
                                    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                                    f.Icon = tex; f._tex = tex
                                    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
                                    cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetDrawBling(false)
                                    cd:SetHideCountdownNumbers(true)
                                    f.Cooldown = cd; f._cooldown = cd
                                    f._isItemPresetFrame = true
                                    f._presetItemID = itemID; f._presetData = preset
                                    f.cooldownID = nil; f.cooldownInfo = nil
                                    f.layoutIndex = 99999
                                    _presetFrames[fkey] = f
                                end
                            end
                            if f then
                                -- Check cooldown (try C_Container first, then C_Item, then alts)
                                local getContainerCD = C_Container and C_Container.GetItemCooldown
                                local start, dur, enable
                                if getContainerCD then
                                    start, dur, enable = getContainerCD(itemID)
                                end
                                if not (start and dur and dur > 1.5) then
                                    start, dur, enable = C_Item.GetItemCooldown(itemID)
                                end
                                if not (start and dur and dur > 1.5) and f._presetData and f._presetData.altItemIDs then
                                    for _, altID in ipairs(f._presetData.altItemIDs) do
                                        if getContainerCD then
                                            start, dur, enable = getContainerCD(altID)
                                        end
                                        if not (start and dur and dur > 1.5) then
                                            start, dur, enable = C_Item.GetItemCooldown(altID)
                                        end
                                        if start and dur and dur > 1.5 then break end
                                    end
                                end
                                if start and dur and dur > 1.5 and enable then
                                    f._cooldown:SetCooldown(start, dur)
                                    f._cdStart = start; f._cdDur = dur
                                elseif f._cdStart and f._cdDur and (GetTime() < f._cdStart + f._cdDur) then
                                    -- Item consumed but cached cooldown still active; don't clear
                                else
                                    f._cooldown:Clear()
                                    f._cdStart = nil; f._cdDur = nil
                                end
                                -- Gray out healthstones if not in bags
                                if f._presetData and (f._presetData.key == "healthstone" or f._presetData.key == "demonic_healthstone") then
                                    local inBags = C_Item.GetItemCount(itemID) > 0
                                    if not inBags and f._presetData.altItemIDs then
                                        for _, altID in ipairs(f._presetData.altItemIDs) do
                                            if C_Item.GetItemCount(altID) > 0 then inBags = true; break end
                                        end
                                    end
                                    if f._tex then f._tex:SetDesaturated(not inBags) end
                                end
                                DecorateFrame(f, barData); f:Show()
                                list[#list + 1] = AcquireEntry(f, sid, sid, spellOrder[sid] or 99999)
                            end
                        elseif sid and sid > 0 then
                            -- Positive spell ID: racial, custom spell, or custom buff
                            local hasClaim = false
                            if not isCustomBuff then
                                for _, e in ipairs(list) do
                                    if e.spellID == sid or e.baseSpellID == sid then hasClaim = true; break end
                                end
                            end
                            if not hasClaim then
                                -- Custom buff bars: only show when aura is active
                                if isCustomBuff then
                                    local euiOpen = EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown()
                                    -- Check primary spell ID + any preset variants
                                    local aura = C_UnitAuras.GetPlayerAuraBySpellID(sid)
                                    if not aura and sd and sd.presetVariants and sd.presetVariants[sid] then
                                        for _, varSid in ipairs(sd.presetVariants[sid]) do
                                            aura = C_UnitAuras.GetPlayerAuraBySpellID(varSid)
                                            if aura then break end
                                        end
                                    end
                                    if not aura and not euiOpen then
                                        -- Hide frame if it exists
                                        local fkey = barKey .. ":custombuff:" .. sid
                                        local f = _presetFrames[fkey]
                                        if f then f:Hide() end
                                    else
                                        -- Aura active — create/show frame
                                        local fkey = barKey .. ":custombuff:" .. sid
                                        local f = _presetFrames[fkey]
                                        if not f then
                                            f = CreateFrame("Frame", nil, UIParent)
                                            f:SetSize(36, 36); f:Hide()
                                            local tex = f:CreateTexture(nil, "ARTWORK")
                                            tex:SetAllPoints(); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                                            f.Icon = tex; f._tex = tex
                                            local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
                                            cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetDrawBling(false)
                                            cd:SetHideCountdownNumbers(true); cd:SetReverse(true)
                                            f.Cooldown = cd; f._cooldown = cd
                                            f._isCustomSpellFrame = true
                                            f.cooldownID = nil; f.cooldownInfo = nil
                                            f.layoutIndex = 99999
                                            _presetFrames[fkey] = f
                                            -- Cache spell icon on creation
                                            local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
                                            if spInfo and spInfo.iconID and f._tex then f._tex:SetTexture(spInfo.iconID) end
                                        end
                                        -- Set duration from aura data (nil when EUI preview)
                                        if aura and aura.duration and aura.duration > 0 and aura.expirationTime then
                                            local start = aura.expirationTime - aura.duration
                                            f._cooldown:SetCooldown(start, aura.duration)
                                        else
                                            f._cooldown:Clear()
                                        end
                                        DecorateFrame(f, barData); f:Show()
                                        list[#list + 1] = AcquireEntry(f, sid, sid, spellOrder[sid] or 99999)
                                    end
                                else
                                    -- CD/utility: racial or custom spell (always shown)
                                    local isRacial = ns._myRacialsSet and ns._myRacialsSet[sid]
                                    local fkey = barKey .. ":" .. (isRacial and "racial" or "custom") .. ":" .. sid
                                    local f = _presetFrames[fkey]
                                    if not f then
                                        f = CreateFrame("Frame", nil, UIParent)
                                        f:SetSize(36, 36); f:Hide()
                                        local tex = f:CreateTexture(nil, "ARTWORK")
                                        tex:SetAllPoints(); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                                        f.Icon = tex; f._tex = tex
                                        local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
                                        cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetDrawBling(false)
                                        cd:SetHideCountdownNumbers(true)
                                        f.Cooldown = cd; f._cooldown = cd
                                        f._isRacialFrame = isRacial or nil
                                        f._isCustomSpellFrame = not isRacial or nil
                                        f.cooldownID = nil; f.cooldownInfo = nil
                                        f.layoutIndex = 99999
                                        _presetFrames[fkey] = f
                                    end
                                    local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
                                    if spInfo and spInfo.iconID and f._tex then f._tex:SetTexture(spInfo.iconID) end
                                    if not f._cdSet or f._racialCdDirty then
                                        local durObj = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(sid)
                                        if durObj and f._cooldown.SetCooldownFromDurationObject then
                                            f._cooldown:SetCooldownFromDurationObject(durObj, true)
                                        end
                                        f._cdSet = true; f._racialCdDirty = false
                                    end
                                    DecorateFrame(f, barData); f:Show()
                                    list[#list + 1] = AcquireEntry(f, sid, sid, spellOrder[sid] or 99999)
                                end
                            end
                        end
                    end
                end

                -- Sort
                table.sort(list, _sortBySpellOrder)

                -- Assign to icon slots
                local icons = cdmBarIcons[barKey]
                if not icons then icons = {}; cdmBarIcons[barKey] = icons end
                local count = 0
                local usedFrames = _scratch_usedFrames

                -- Build lookup for matching assignedSpells to viewer frames
                local entryBySpell = {}
                for _, entry in ipairs(list) do
                    if entry.spellID and not entryBySpell[entry.spellID] then entryBySpell[entry.spellID] = entry end
                    if entry.baseSpellID and not entryBySpell[entry.baseSpellID] then entryBySpell[entry.baseSpellID] = entry end
                end

                if spellList and #spellList > 0 then
                    -- Assigned order: iterate spellList, match to entries
                    for _, sid in ipairs(spellList) do
                        if sid and sid ~= 0 then
                            local entry = entryBySpell[sid]
                            if not entry and sid > 0 and _FindOverride then
                                local ovr = _FindOverride(sid)
                                if ovr and ovr > 0 then entry = entryBySpell[ovr] end
                            end
                            if entry and not usedFrames[entry.frame] then
                                count = count + 1
                                local frame = entry.frame
                                usedFrames[frame] = true
                                DecorateFrame(frame, barData)
                                if frame:GetScale() ~= 1 then frame:SetScale(1) end
                                -- No SetParent — it taints the frame (causes secret value
                                -- errors on charges/hasTotem). Blizzard's Layout may
                                -- reposition frames, but our reanchor fixes them back.
                                FC(frame).barKey = barKey
                                FC(frame).spellID = entry.baseSpellID or entry.spellID
                                icons[count] = frame
                                if barHidden then
                                    frame:ClearAllPoints()
                                    frame:SetPoint("CENTER", UIParent, "TOPLEFT", -10000, 10000)
                                end
                                local isOurs = frame._isRacialFrame or frame._isTrinketFrame or frame._isPresetFrame or frame._isItemPresetFrame or frame._isCustomSpellFrame
                                if isOurs then
                                    if barHidden then frame:Hide() else frame:Show() end
                                end
                            end
                        end
                    end
                else
                    -- No assignedSpells: use list order directly
                    for _, entry in ipairs(list) do
                        count = count + 1
                        local frame = entry.frame
                        usedFrames[frame] = true
                        DecorateFrame(frame, barData)
                        if frame:GetScale() ~= 1 then frame:SetScale(1) end
                        -- No SetParent — it taints the frame (causes secret value
                        -- errors on charges/hasTotem). Blizzard's Layout may
                        -- reposition frames, but our reanchor fixes them back.
                        FC(frame).barKey = barKey
                        FC(frame).spellID = entry.baseSpellID or entry.spellID
                        icons[count] = frame
                        if barHidden then
                            frame:ClearAllPoints()
                            frame:SetPoint("CENTER", UIParent, "TOPLEFT", -10000, 10000)
                        end
                    end
                end

                -- Clear excess icons
                for i = count + 1, #icons do
                    if icons[i] then
                        icons[i]:ClearAllPoints()
                        icons[i]:SetPoint("CENTER", UIParent, "TOPLEFT", -10000, 10000)
                    end
                    icons[i] = nil
                end

                -- Only refresh/layout if the icon set actually changed.
                -- Avoids sub-pixel rounding drift from unnecessary repositioning.
                local prevCount = container._prevVisibleCount or 0
                local iconsChanged = count ~= prevCount
                if not iconsChanged and container._prevIconRefs then
                    for idx = 1, count do
                        if container._prevIconRefs[idx] ~= icons[idx] then
                            iconsChanged = true; break
                        end
                    end
                else
                    iconsChanged = true
                end
                if iconsChanged then
                    if RefreshCDMIconAppearance then RefreshCDMIconAppearance(barKey) end
                    if LayoutCDMBar then LayoutCDMBar(barKey) end
                    if ApplyCDMTooltipState then ApplyCDMTooltipState(barKey) end
                    if not container._prevIconRefs then container._prevIconRefs = {} end
                    for idx = 1, count do container._prevIconRefs[idx] = icons[idx] end
                    for idx = count + 1, #container._prevIconRefs do container._prevIconRefs[idx] = nil end
                end
                container._prevVisibleCount = count
            end
        end
    end

    -- Clean up empty bars
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and not barLists[bd.key] then
            local icons = cdmBarIcons[bd.key]
            if icons then
                for i = 1, #icons do
                    if icons[i] then
                        icons[i]:ClearAllPoints()
                        icons[i]:SetPoint("CENTER", UIParent, "TOPLEFT", -10000, 10000)
                    end
                    icons[i] = nil
                end
            end
            local container = cdmBarFrames[bd.key]
            if container and (container._prevVisibleCount or 0) > 0 then
                container._prevVisibleCount = 0
                if LayoutCDMBar then LayoutCDMBar(bd.key) end
            end
        end
    end

    -- 6. Unclaimed frames: alpha 0. Claimed frames: restore alpha 1.
    for frame in pairs(allActiveFrames) do
        if not _scratch_usedFrames[frame] then
            frame:SetAlpha(0)
        elseif frame:GetAlpha() == 0 then
            frame:SetAlpha(1)
        end
    end

    if ns.UpdateOverlayVisuals then ns.UpdateOverlayVisuals() end
    ns.RefreshAllOverlays()

end
ns.CollectAndReanchor = CollectAndReanchor

-------------------------------------------------------------------------------
--  RefreshAllOverlays (centralized)
--  Runs after every reanchor. Checks each icon/bar against Blizzard's
--  tracked sets and shows/hides the "Click to Track" overlay.
--
--  Rules:
--    CD/utility bar icon: must be in Essential/Utility viewer (_cdUtilTrackedSet)
--    Buff bar icon: must be in BuffIcon viewer (_buffIconTrackedSet)
--    TBB bar: must be in BuffBar viewer (_barViewerCache)
-------------------------------------------------------------------------------
function ns.RefreshAllOverlays()
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars then return end
    local ApplyOverlay = ns.ApplyUntrackedOverlay
    if not ApplyOverlay then return end

    -- CDM bar icons
    for _, barData in ipairs(p.cdmBars.bars) do
        if barData.enabled then
            local icons = cdmBarIcons[barData.key]
            if icons then
                local barType = barData.barType or barData.key
                local isBuff = (barType == "buffs")
                for _, icon in ipairs(icons) do
                    -- Skip our own frames (racials, trinkets, presets, items)
                    -- They aren't tracked via Blizzard CDM so overlays don't apply.
                    if icon._isRacialFrame or icon._isTrinketFrame
                       or icon._isPresetFrame or icon._isItemPresetFrame
                       or icon._isCustomSpellFrame then
                        ApplyOverlay(icon, false)
                    else
                        local fc = _ecmeFC[icon]
                        local sid = fc and fc.spellID
                        if sid and sid > 0 then
                            local tracked
                            if isBuff then
                                tracked = _buffIconTrackedSet[sid]
                            else
                                tracked = _cdUtilTrackedSet[sid]
                            end
                            ApplyOverlay(icon, not tracked)
                        end
                    end
                end
            end
        end
    end

    -- TBB (Tracking Bars)
    local ShowTBB = ns.ShowTBBUntrackedOverlay
    local HideTBB = ns.HideTBBUntrackedOverlay
    if ShowTBB and HideTBB then
        local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
        local bars = tbb and tbb.bars
        if bars then
            for i, cfg in ipairs(bars) do
                local bar = ns.GetTBBFrame and ns.GetTBBFrame(i)
                if bar and cfg.enabled ~= false then
                    local hasSpell = (cfg.spellID and cfg.spellID > 0) or (cfg.spellIDs and #cfg.spellIDs > 0)
                    -- Skip overlay for racials/non-CDM spells
                    local isNonCDM = false
                    if cfg.spellID and cfg.spellID > 0 then
                        isNonCDM = (ns._myRacialsSet and ns._myRacialsSet[cfg.spellID])
                    end
                    if hasSpell and not cfg.popularKey and not isNonCDM then
                        local tracked = false
                        if cfg.spellIDs then
                            for _, sid in ipairs(cfg.spellIDs) do
                                if _barViewerCache[sid] then tracked = true; break end
                            end
                        elseif cfg.spellID and cfg.spellID > 0 then
                            tracked = _barViewerCache[cfg.spellID]
                        end
                        if not tracked then
                            ShowTBB(bar, cfg)
                        else
                            HideTBB(bar)
                        end
                    else
                        HideTBB(bar)
                    end
                end
            end
        end
    end
end

-- CheckAura removed — custom aura bars now use cooldown-based detection.

-------------------------------------------------------------------------------
--  UpdateCustomBuffBars
--  Dedicated update for custom_buff (Custom Aura) bars.
--  Uses SPELL_UPDATE_COOLDOWN to detect spell usage, then shows icon with
--  a hardcoded duration (reverse cooldown swipe). No C_UnitAuras.
--  Triggered by the racial cooldown listener (SPELL_UPDATE_COOLDOWN).
-------------------------------------------------------------------------------

-- Active timers: [barKey:sid] = { start = GetTime(), duration = N }
local _customAuraTimers = {}

local function UpdateCustomBuffBars()
    if CooldownViewerSettings and CooldownViewerSettings:IsShown() then return end
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars or not p.cdmBars.bars then return end
    local LayoutCDMBar = ns.LayoutCDMBar
    local RefreshCDMIconAppearance = ns.RefreshCDMIconAppearance
    local euiOpen = EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown()
    local now = GetTime()

    for _, barData in ipairs(p.cdmBars.bars) do
        if barData.enabled and barData.barType == "custom_buff" then
            local barKey = barData.key
            local container = cdmBarFrames[barKey]
            if container then
                local sd = ns.GetBarSpellData(barKey)
                local spellList = sd and sd.assignedSpells or {}

                local icons = cdmBarIcons[barKey]
                if not icons then icons = {}; cdmBarIcons[barKey] = icons end
                local count = 0

                for _, sid in ipairs(spellList) do
                    if type(sid) == "number" and sid > 0 then
                        local duration = sd.spellDurations and sd.spellDurations[sid] or 0
                        if duration > 0 then
                        local timerKey = barKey .. ":" .. sid
                        local timer = _customAuraTimers[timerKey]

                        -- Detect via UNIT_SPELLCAST_SUCCEEDED: exact spell match.
                        -- _pendingCastIDs accumulates cast IDs from the event handler.
                        if _pendingCastIDs[sid] and duration > 0 then
                            _customAuraTimers[timerKey] = {
                                start = now,
                                duration = duration,
                            }
                            timer = _customAuraTimers[timerKey]
                        end

                        local isActive = timer and duration > 0
                            and (now - timer.start) < timer.duration

                        if isActive or euiOpen then
                            local fkey = barKey .. ":custombuff:" .. sid
                            local f = _presetFrames[fkey]
                            if not f then
                                f = CreateFrame("Frame", nil, UIParent)
                                f:SetSize(36, 36); f:Hide()
                                local tex = f:CreateTexture(nil, "ARTWORK")
                                tex:SetAllPoints(); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                                f.Icon = tex; f._tex = tex
                                local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
                                cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetDrawBling(false)
                                cd:SetHideCountdownNumbers(not barData.showCooldownText)
                                cd:SetReverse(true)
                                f.Cooldown = cd; f._cooldown = cd
                                f._isCustomSpellFrame = true
                                f.cooldownID = nil; f.cooldownInfo = nil
                                f.layoutIndex = 99999
                                _presetFrames[fkey] = f
                                -- Hook OnCooldownDone to trigger update when timer expires
                                cd:HookScript("OnCooldownDone", function()
                                    C_Timer.After(0, QueueCustomBuffUpdate)
                                end)
                                -- Cache spell icon on creation
                                local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
                                if spInfo and spInfo.iconID and f._tex then f._tex:SetTexture(spInfo.iconID) end
                            end
                            if isActive then
                                f._cooldown:SetCooldown(timer.start, timer.duration)
                            else
                                f._cooldown:Clear()
                            end
                            DecorateFrame(f, barData); f:Show()
                            count = count + 1
                            icons[count] = f
                        else
                            -- Expired or never started
                            local fkey = barKey .. ":custombuff:" .. sid
                            local f = _presetFrames[fkey]
                            if f then f:Hide() end
                            if timer and not isActive then
                                _customAuraTimers[timerKey] = nil
                            end
                        end
                        end -- duration > 0 (skip glow reps)
                    end
                end

                -- Clear excess
                for i = count + 1, #icons do
                    if icons[i] then icons[i]:Hide() end
                    icons[i] = nil
                end

                -- Layout if changed
                local prevCount = container._prevVisibleCount or 0
                if count ~= prevCount then
                    if RefreshCDMIconAppearance then RefreshCDMIconAppearance(barKey) end
                    if LayoutCDMBar then LayoutCDMBar(barKey) end
                end
                container._prevVisibleCount = count

            end -- container check
        end
    end
    -- Consume pending cast IDs so they don't re-trigger on next call
    wipe(_pendingCastIDs)
end
ns.UpdateCustomBuffBars = UpdateCustomBuffBars

-------------------------------------------------------------------------------
--  Custom Buff Bar UNIT_AURA management
--  Only registers UNIT_AURA when at least one custom_buff bar has spells.
--  Debounced to avoid excessive reanchors from aura ticks.
-------------------------------------------------------------------------------
-- UNIT_AURA removed — custom aura bars use SPELL_UPDATE_COOLDOWN instead.
-- UpdateCustomBuffAuraTracking kept as no-op for callers that reference it.
function ns.UpdateCustomBuffAuraTracking() end

--- Queue a reanchor for the next OnUpdate frame.
local function QueueReanchor()
    reanchorDirty = true
    if reanchorFrame then reanchorFrame:Show() end
end
ns.QueueReanchor = QueueReanchor

local REANCHOR_THROTTLE = 0.05
local _lastReanchorTime = 0
local function ProcessReanchorQueue(self)
    if not reanchorDirty then self:Hide(); return end
    local now = GetTime()
    if now - _lastReanchorTime < REANCHOR_THROTTLE then return end
    reanchorDirty = false
    _lastReanchorTime = now
    CollectAndReanchor()
    if ns.CDMApplyVisibility then ns.CDMApplyVisibility() end
end

--- Install hooks on Blizzard CDM viewer mixins and frame pools.
function ns.SetupViewerHooks()
    if viewerHooksInstalled then return end
    viewerHooksInstalled = true

    reanchorFrame = CreateFrame("Frame")
    reanchorFrame:SetScript("OnUpdate", ProcessReanchorQueue)
    reanchorFrame:Hide()

    ns.SyncViewerToContainer = function() end

    -- Lightweight Layout hook for ALL viewers: re-apply our icon positions
    -- after Blizzard's Layout repositions them. Just SetSize + SetPoint,
    -- no pool iteration or spell resolution.
    for viewerName in pairs(HOOK_VIEWER_TO_BAR) do
        local viewer = _G[viewerName]
        if viewer and viewer.Layout then
            hooksecurefunc(viewer, "Layout", function()
                local LCB = ns.LayoutCDMBar
                if not LCB then return end
                for barKey, icons in pairs(cdmBarIcons) do
                    if icons and #icons > 0 then
                        LCB(barKey)
                    end
                end
            end)
        end
    end

    -- Blizzard CDM settings panel: reanchor when user finishes editing
    -- (spells moved between sections). Only fires on user action, not
    -- during internal icon swaps.
    if CooldownViewerSettings then
        CooldownViewerSettings:HookScript("OnHide", function()
            C_Timer.After(0.3, QueueReanchor)
            -- Prompt reload after editing Blizzard CDM settings
            EllesmereUI:ShowConfirmPopup({
                title = "Reload Required",
                message = "Changes to the Blizzard Cooldown Manager require a UI reload to avoid potential errors.",
                confirmText = "Reload Now",
                cancelText = "Later",
                onConfirm = function() ReloadUI() end,
            })
        end)
    end

    -- EUI options panel: reanchor when opened/closed so custom aura
    -- preview icons and overlays update correctly.
    EllesmereUI:RegisterOnShow(function()
        C_Timer.After(0.1, function()
            QueueReanchor()
            UpdateCustomBuffBars()
        end)
    end)
    EllesmereUI:RegisterOnHide(function()
        C_Timer.After(0.1, function()
            QueueReanchor()
            UpdateCustomBuffBars()
        end)
    end)

    -- Buff icon detection is handled by per-frame hooks installed in
    -- CollectAndReanchor (OnActiveStateChanged, OnUnitAuraAddedEvent,
    -- OnUnitAuraRemovedEvent on each child — same as CMC).
    -- RefreshLayout on BuffIconCooldownViewer also triggers via the
    -- lightweight Layout hook above for re-positioning.

    C_Timer.After(0.2, function()
        QueueReanchor()
        UpdateCustomBuffBars()
    end)
end

function ns.IsViewerHooked()
    return viewerHooksInstalled
end
