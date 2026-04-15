-------------------------------------------------------------------------------
--  EllesmereUICdmHooks.lua  (v5 -- Mixin Hook Architecture)
--
--  CORE PRINCIPLE: Blizzard manages all cooldown/buff state.
--  We ONLY restyle (borders, shapes, fonts) and reposition (into our bars).
--
--  Hook strategy:
--    - OnCooldownIDSet on all 4 Blizzard CDM mixins -> QueueReanchor
--    - Pool Acquire on all viewers -> QueueReanchor
--    - Viewer Layout hooks -> QueueReanchor (catches frame removals)
--
--  Taint prevention:
--    - Never SetParent/SetScale/Hide/Show on Blizzard frames
--    - Never move Blizzard frames offscreen
--    - Never write custom keys to Blizzard frame tables
--    - All per-frame data in external weak-keyed tables
--    - Unclaimed frames: SetAlpha(0). Claimed: SetAlpha(1).
-------------------------------------------------------------------------------
local _, ns = ...

local ECME               = ns.ECME
local barDataByKey        = ns.barDataByKey
local cdmBarFrames        = ns.cdmBarFrames
local cdmBarIcons         = ns.cdmBarIcons
local MAIN_BAR_KEYS       = ns.MAIN_BAR_KEYS
local ResolveInfoSpellID  = ns.ResolveInfoSpellID
local GetCDMFont          = ns.GetCDMFont

local floor   = math.floor
local GetTime = GetTime

-------------------------------------------------------------------------------
--  Memory Profiling (temporary)
-------------------------------------------------------------------------------
local _memProf = {}
local _memProfLast = 0
local function MemSnap(label)
    local kb = collectgarbage("count")
    if not _memProf[label] then _memProf[label] = { total = 0, calls = 0, peak = 0 } end
    _memProf[label]._pre = kb
end
local function MemDelta(label)
    local p = _memProf[label]
    if not p or not p._pre then return end
    local delta = collectgarbage("count") - p._pre
    p.total = p.total + delta
    p.calls = p.calls + 1
    if delta > p.peak then p.peak = delta end
    p._pre = nil
end
local function MemReport()
    local now = GetTime()
    if now - _memProfLast < 10 then return end
    _memProfLast = now
    local sorted = {}
    for k, v in pairs(_memProf) do
        sorted[#sorted + 1] = { name = k, total = v.total, calls = v.calls, peak = v.peak }
    end
    table.sort(sorted, function(a, b) return a.total > b.total end)
    -- print("|cff00ffff[CDM MEM]|r Top allocators (last 10s):")
    -- for i = 1, math.min(8, #sorted) do
    --     local e = sorted[i]
    --     print(string.format("  %s: %.1f KB total, %d calls, %.2f KB peak",
    --         e.name, e.total, e.calls, e.peak))
    -- end
    for k in pairs(_memProf) do _memProf[k] = { total = 0, calls = 0, peak = 0 } end
end
ns._MemSnap = MemSnap
ns._MemDelta = MemDelta

-- Per-frame decoration state (weak-keyed)
local hookFrameData = setmetatable({}, { __mode = "k" })
ns._hookFrameData = hookFrameData

-- External frame cache from main file
local _ecmeFC = ns._ecmeFC
local FC = ns.FC

local function FD(f)
    local d = hookFrameData[f]
    if not d then d = {}; hookFrameData[f] = d end
    return d
end
ns.FD = FD

-------------------------------------------------------------------------------
--  Constants
-------------------------------------------------------------------------------
local VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

local VIEWER_TO_BAR = {
    EssentialCooldownViewer = "cooldowns",
    UtilityCooldownViewer   = "utility",
    BuffIconCooldownViewer  = "buffs",
}

-- Master guard: suspend ALL hook logic while Blizzard CDM settings is open.
-- Any interaction with frames during settings editing causes taint.
local function IsCDMSettingsOpen()
    return CooldownViewerSettings and CooldownViewerSettings:IsShown()
end

-------------------------------------------------------------------------------
--  Spell ID Resolution
-------------------------------------------------------------------------------
local function ResolveFrameSpellID(frame)
    local cdID = frame.cooldownID
    if not cdID and frame.cooldownInfo then
        cdID = frame.cooldownInfo.cooldownID
    end
    if not cdID or not C_CooldownViewer then return nil, nil end

    local fc = _ecmeFC[frame]
    if fc and fc.resolvedSid and fc.cachedCdID == cdID then
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
    fc.cachedCdID  = cdID
    fc.cachedAuraInstID = frame.auraInstanceID

    if info.linkedSpellIDs and #info.linkedSpellIDs > 0 then
        fc.linkedSpellIDs = info.linkedSpellIDs
    else
        fc.linkedSpellIDs = nil
    end

    return displaySID, baseSID
end
ns.ResolveFrameSpellID = ResolveFrameSpellID

-------------------------------------------------------------------------------
--  Spell Routing State
--
--  _divertedSpellsBuff / _divertedSpellsCD:
--                   variant-keyed maps of every spell ID claimed by a bar.
--                   Split by viewer family so the same spellID (e.g. Divine
--                   Shield 642, which exists as both a cooldown in the
--                   essential viewer AND a buff in the buff viewer) can
--                   route independently per family. Without the split, a
--                   later pass writing the same spellID for a different
--                   family would clobber the earlier pass and the frame
--                   would fall through to its viewer default.
--                   Built once by RebuildSpellRouteMap from the bar list.
--                   Queried per-frame at reanchor time by ResolveCDIDToBar
--                   using the viewer's family.
--
--  _cdidRouteMap:   memoization cache, cooldownID -> barKey. Lazily
--                   populated by ResolveCDIDToBar on first lookup. Wiped
--                   by RebuildSpellRouteMap. Safe as a single map because
--                   a given cooldownID only exists in ONE viewer, so the
--                   buff-vs-CD family is already implicit in the key.
-------------------------------------------------------------------------------
local _cdidRouteMap = {}

local _divertedSpellsBuff = {}
local _divertedSpellsCD   = {}
ns._divertedSpellsBuff = _divertedSpellsBuff
ns._divertedSpellsCD   = _divertedSpellsCD

-- Sentinel: set true at the end of RebuildSpellRouteMap on a successful
-- build. CollectAndReanchor's safety net tests this (NOT _cdidRouteMap,
-- which is a lazy cache and intentionally empty post-build, NOT the
-- diversion maps, which can legitimately be empty for users with no
-- diversions).
local _routeMapBuilt = false

--- Rebuild the diversion set. The cdID->bar route is computed lazily at
--- reanchor time via ResolveCDIDToBar (below) which uses the FRAME's actual
--- viewerFrame as the source-of-truth default, not the static category API.
---
--- Why frame-driven default routing instead of category API:
---   Blizzard's GetCooldownViewerCategorySet returns the STATIC category
---   for a cooldownID. But Blizzard's actual CDM viewer can show a spell
---   in a different viewer than its static category (e.g. user dragged
---   Lay on Hands from Essential to Utility in Edit Mode, OR a per-spec
---   layout reassigns it). The viewer the FRAME is in is the user-visible
---   ground truth.
---
--- Default bars contribute to the diversion set: putting a spellID into
--- cooldowns.assignedSpells or utility.assignedSpells is how the user says
--- "this spell goes on this default bar regardless of viewer category."
--- This enables cross-routing between default bars (e.g. Lay on Hands in
--- Essential viewer routed to utility bar via utility.assignedSpells).
---
--- Priority for collisions (rare under the 1-spell-per-bar invariant):
---   ghost bars (lowest) -> custom buff -> custom CD/util -> default bars
---   (highest). Later passes overwrite earlier via preserveExisting=false.
---
--- Family split: each bar writes to either _divertedSpellsBuff (buff
--- family) or _divertedSpellsCD (non-buff family). This prevents a
--- buff-family bar and a CD-family bar from clobbering each other's
--- diversion entries when they both claim the same spellID (e.g. Divine
--- Shield, which has a cooldown frame AND a buff frame under the same
--- spellID 642).
function ns.RebuildSpellRouteMap()
    wipe(_cdidRouteMap)
    wipe(_divertedSpellsBuff)
    wipe(_divertedSpellsCD)
    _routeMapBuilt = false

    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars then return end

    local SVV = ns.StoreVariantValue
    if not SVV then return end

    local IsBuffFamily = ns.IsBarBuffFamily

    local function CollectDiversionsFor(bd)
        local sd = ns.GetBarSpellData(bd.key)
        if not sd or not sd.assignedSpells then return end
        local targetMap = IsBuffFamily and IsBuffFamily(bd) and _divertedSpellsBuff or _divertedSpellsCD
        for _, sid in ipairs(sd.assignedSpells) do
            if type(sid) == "number" and sid > 0 then
                SVV(targetMap, sid, bd.key, false)
            end
        end
    end

    -- Pass 1: ghost bars (lowest priority)
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and bd.isGhostBar then
            CollectDiversionsFor(bd)
        end
    end
    -- Pass 2: custom buff bars (extra buff bars) + custom_buff (TBB) bars.
    -- TBB bars compete for the same buff icon spells, so their diversions
    -- must land in _divertedSpellsBuff even though IsBarBuffFamily returns
    -- false for custom_buff. We write directly to _divertedSpellsBuff here.
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and not bd.isGhostBar
           and ((bd.barType == "buffs" and bd.key ~= "buffs")
                or bd.barType == "custom_buff") then
            local sd = ns.GetBarSpellData(bd.key)
            if sd and sd.assignedSpells then
                for _, sid in ipairs(sd.assignedSpells) do
                    if type(sid) == "number" and sid > 0 then
                        SVV(_divertedSpellsBuff, sid, bd.key, false)
                    end
                end
            end
        end
    end
    -- Pass 3: custom CD/utility bars
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and not bd.isGhostBar
           and bd.key ~= "cooldowns" and bd.key ~= "utility" and bd.key ~= "buffs"
           and bd.barType ~= "buffs" and bd.barType ~= "custom_buff" then
            CollectDiversionsFor(bd)
        end
    end
    -- Pass 4: default bars (highest priority -- the user's explicit
    -- assignment to a default bar overrides everything)
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and not bd.isGhostBar
           and (bd.key == "cooldowns" or bd.key == "utility" or bd.key == "buffs") then
            CollectDiversionsFor(bd)
        end
    end

    _routeMapBuilt = true
end

--- Lazily resolve a cooldownID to a bar key. Called per-frame at reanchor
--- time. Uses _cdidRouteMap as a memoization cache; on cache miss, computes
--- the route from the per-family diversion map or falls back to
--- viewerDefaultBar (the bar that owns the viewer the frame came from).
--- Caches the result.
---
--- viewerDefaultBar is "cooldowns" / "utility" / "buffs" depending on which
--- viewer pool the frame was enumerated from -- this is the user-visible
--- ground truth, not the static category API. It also tells us which
--- family to consult (buffs -> _divertedSpellsBuff, otherwise CD).
local function ResolveCDIDToBar(cdID, viewerDefaultBar)
    if not cdID then return viewerDefaultBar end
    local cached = _cdidRouteMap[cdID]
    if cached then return cached end

    local RVV = ns.ResolveVariantValue
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    if not RVV or not gci then
        _cdidRouteMap[cdID] = viewerDefaultBar
        return viewerDefaultBar
    end

    local divertMap = (viewerDefaultBar == "buffs") and _divertedSpellsBuff or _divertedSpellsCD

    local info = gci(cdID)
    local routedBar = nil
    if info then
        if info.spellID and info.spellID > 0 then
            routedBar = RVV(divertMap, info.spellID)
        end
        if not routedBar and info.overrideSpellID and info.overrideSpellID > 0
           and info.overrideSpellID ~= info.spellID then
            routedBar = RVV(divertMap, info.overrideSpellID)
        end
        if not routedBar and info.linkedSpellIDs then
            for _, lid in ipairs(info.linkedSpellIDs) do
                if type(lid) == "number" and lid > 0 then
                    routedBar = RVV(divertMap, lid)
                    if routedBar then break end
                end
            end
        end
    end

    routedBar = routedBar or viewerDefaultBar
    _cdidRouteMap[cdID] = routedBar
    return routedBar
end
ns.ResolveCDIDToBar = ResolveCDIDToBar
ns._cdidRouteMap = _cdidRouteMap

-------------------------------------------------------------------------------
--  Active aura cache (consumed by bar glow overlays)
--
--  Maintained by the 0.1s buff ticker, NOT here. The ticker walks viewer
--  pools cheaply and writes spellID->true for any frame whose Blizzard-set
--  wasSetFromAura/auraInstanceID indicates an active aura. Bar glows read
--  via ns._tickBlizzActiveCache.
-------------------------------------------------------------------------------
local _activeCache = {}
ns._tickBlizzActiveCache = _activeCache

-------------------------------------------------------------------------------
--  IsFrameIncluded
--  Include if shown OR has cooldownInfo (catches transitional frames).
-------------------------------------------------------------------------------
local function IsFrameIncluded(frame)
    if not frame then return false end
    return frame:IsShown() or (frame.cooldownInfo ~= nil)
end

-------------------------------------------------------------------------------
--  HideBlizzardDecorations
--  Strip Blizzard visual chrome from a CDM frame (one-time per frame).
-------------------------------------------------------------------------------
local function HideBlizzardDecorations(frame)
    local fc = FC(frame)
    if fc.blizzHidden then return end
    fc.blizzHidden = true

    local function alphaZero(child)
        if child then child:SetAlpha(0) end
    end
    alphaZero(frame.Border)
    if frame.SpellActivationAlert then
        frame.SpellActivationAlert:SetAlpha(0)
        frame.SpellActivationAlert:Hide()
    end
    alphaZero(frame.Shadow)
    alphaZero(frame.IconShadow)
    alphaZero(frame.DebuffBorder)
    alphaZero(frame.CooldownFlash)

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

    -- Do NOT call SetHideCountdownNumbers. Use SetCountdownFont
    -- to control countdown text display instead of hiding numbers entirely.
end

-------------------------------------------------------------------------------
--  DecorateFrame
--  Add our visual overlays to a CDM frame (one-time per frame).
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

    HideBlizzardDecorations(frame)

    -- Hook SetPoint: when Blizzard repositions this frame (via Layout,
    -- RefreshLayout, or internal updates), force it back to the stored
    -- CDM anchor position if Blizzard tries to reposition it.
    if not fd._setPointHooked then
        fd._setPointHooked = true
        hooksecurefunc(frame, "SetPoint", function(_, point, relativeTo)
            local anchor = fd._cdmAnchor
            if not anchor then return end
            -- If relativeTo is already our bar container, this is our own
            -- SetPoint call from LayoutCDMBar. Don't intercept.
            if relativeTo == anchor[2] then return end
            -- Blizzard is trying to move us. Force back to CDM position.
            frame:ClearAllPoints()
            frame:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
        end)
    end


    -- Per-icon active state hooks installed lazily during CollectAndReanchor,
    -- ONLY for spells with custom active state settings.

    if not fd.bg then
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(barData.bgR or 0.08, barData.bgG or 0.08,
            barData.bgB or 0.08, barData.bgA or 0.6)
        fd.bg = bg
    end

    if not fd.glowOverlay then
        local go = CreateFrame("Frame", nil, frame)
        go:SetAllPoints(frame)
        go:SetFrameLevel(frame:GetFrameLevel() + 6)
        go:SetAlpha(0)
        go:EnableMouse(false)
        fd.glowOverlay = go
    end

    if not fd.textOverlay then
        local txo = CreateFrame("Frame", nil, frame)
        txo:SetAllPoints(frame)
        txo:SetFrameLevel(25)
        txo:EnableMouse(false)
        fd.textOverlay = txo
    end

    if not fd.keybindText then
        local kt = fd.textOverlay:CreateFontString(nil, "OVERLAY")
        local kbScale = frame:GetScale() or 1
        if kbScale < 0.01 then kbScale = 1 end
        kt:SetFont(GetCDMFont(), (barData.keybindSize or 10) / kbScale, "OUTLINE")
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

    if not fd.borderFrame then
        local bf = CreateFrame("Frame", nil, frame)
        bf:SetAllPoints(frame)
        bf:SetFrameLevel(frame:GetFrameLevel() + 5)
        fd.borderFrame = bf
        EllesmereUI.PP.CreateBorder(bf,
            barData.borderR or 0, barData.borderG or 0,
            barData.borderB or 0, barData.borderA or 1,
            barData.borderSize or 1, "OVERLAY", 7)
    end

    fd.procGlowActive = false

    if fd.cooldown then
        fd.cooldown:SetDrawEdge(false)
        -- Swipe starts disabled. CollectAndReanchor enables it once the
        -- frame is claimed and positioned on a bar. This prevents a flash
        -- of black swipe at the Blizzard viewer's default position before
        -- our reanchor runs.
        fd.cooldown:SetDrawSwipe(false)
        fd.cooldown:SetDrawBling(false)
        fd._isProcessingOverride = true
        fd.cooldown:SetSwipeColor(0, 0, 0, barData.swipeAlpha or 0.7)
        fd._isProcessingOverride = false
        fd.cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
        -- Hook SetSwipeColor on EVERY CD/utility frame.
        -- Forces our swipe color (default black, or per-spell custom)
        -- so Blizzard's active state color flash never shows.
        -- Also hook SetDrawSwipe to keep swipe visible on charge spells.
        if not fd._swipeColorHooked then
            fd._swipeColorHooked = true
            local cd = fd.cooldown
            hooksecurefunc(cd, "SetSwipeColor", function()
                if fd._isProcessingOverride then return end
                fd._isProcessingOverride = true
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                local bk2 = fc2 and fc2.barKey
                -- Check per-spell settings
                local ss2
                if sid2 and bk2 then
                    local sd2 = ns.GetBarSpellData(bk2)
                    ss2 = sd2 and sd2.spellSettings and sd2.spellSettings[sid2]
                end
                -- Detect active state from swipe color
                local swipeColor = frame.cooldownSwipeColor
                local isActive = false
                if swipeColor and type(swipeColor) ~= "number" and swipeColor.GetRGBA then
                    local r = swipeColor:GetRGBA()
                    if r and type(r) == "number" and not issecretvalue(r) then
                        isActive = (r ~= 0)
                    end
                end

                if ss2 and ss2.activeSwipeMode == "none" then
                    -- Hide Active State: force black swipe, track active flag.
                    -- CD model override is handled by the SetDesaturation hook
                    -- which fires on every Blizzard cooldown tick.
                    cd:SetSwipeColor(0, 0, 0, barData.swipeAlpha or 0.7)
                    if isActive then
                        fd._hideActiveOverriding = true
                        fd._wasActive = true
                    elseif fd._hideActiveOverriding then
                        fd._hideActiveOverriding = false
                        if cd.SetUseAuraDisplayTime then
                            cd:SetUseAuraDisplayTime(true)
                        end
                    end
                elseif isActive then
                    -- Active: apply swipe color (custom, class, or default #FFC660)
                    local cr, cg, cb, ca
                    if ss2 and ss2.activeSwipeClassColor then
                        local _, ct = UnitClass("player")
                        if ct then
                            local cc = RAID_CLASS_COLORS[ct]
                            if cc then cr, cg, cb = cc.r, cc.g, cc.b end
                        end
                    end
                    cr = cr or (ss2 and ss2.activeSwipeR) or 1
                    cg = cg or (ss2 and ss2.activeSwipeG) or 0.776
                    cb = cb or (ss2 and ss2.activeSwipeB) or 0.376
                    ca = (ss2 and ss2.activeSwipeA) or 0.7
                    cd:SetSwipeColor(cr, cg, cb, ca)
                    if fd.tex then fd.tex:SetDesaturated(false) end
                    fd._wasActive = true
                else
                    -- Not active: black swipe.
                    cd:SetSwipeColor(0, 0, 0, barData.swipeAlpha or 0.7)
                    -- Transition: buff just ended, CD starting. Re-apply the
                    -- cooldown duration so the swipe shows immediately
                    -- (e.g. Invoke Niuzao). Only fires once per transition,
                    -- and only if the spell actually has an active cooldown.
                    if fd._wasActive then
                        fd._wasActive = false
                        if sid2 and cd.SetCooldownFromDurationObject and C_Spell.GetSpellCooldown then
                            local cdInfo = C_Spell.GetSpellCooldown(sid2)
                            if cdInfo and cdInfo.isActive then
                                local durObj = C_Spell.GetSpellCooldownDuration(sid2)
                                if durObj then
                                    cd:SetCooldownFromDurationObject(durObj)
                                    cd:SetDrawSwipe(true)
                                end
                            end
                        end
                    end
                end

                -- Active glow (per-spell)
                local hasGlow2 = ss2 and ss2.activeGlow and ss2.activeGlow > 0
                if isActive and hasGlow2 then
                    if fd.glowOverlay and not fd._activeGlowOn then
                        local gr, gg, gb
                        if ss2.activeGlowClassColor then
                            local _, ct = UnitClass("player")
                            if ct then
                                local cc = RAID_CLASS_COLORS[ct]
                                if cc then gr, gg, gb = cc.r, cc.g, cc.b end
                            end
                        end
                        gr = gr or (ss2.activeGlowR or 1)
                        gg = gg or (ss2.activeGlowG or 0.85)
                        gb = gb or (ss2.activeGlowB or 0)
                        ns.StartNativeGlow(fd.glowOverlay, ss2.activeGlow, gr, gg, gb)
                        fd._activeGlowOn = true
                    end
                elseif fd._activeGlowOn then
                    if fd.glowOverlay then ns.StopNativeGlow(fd.glowOverlay) end
                    fd._activeGlowOn = false
                end

                fd._isProcessingOverride = false
            end)
            hooksecurefunc(cd, "SetDrawSwipe", function(_, show)
                if fd._isProcessingOverride then return end
                if show then return end
                fd._isProcessingOverride = true
                cd:SetDrawSwipe(true)
                fd._isProcessingOverride = false
            end)
        end
        -- Hook SetDesaturated AND SetDesaturation on icon texture: Blizzard
        -- calls these on every cooldown tick. When we're overriding the CD
        -- model (hide active state), re-apply the actual CD duration here so
        -- Blizzard can't revert it between ticks.
        if fd.tex and not fd._desatOverrideHooked then
            fd._desatOverrideHooked = true
            local function onDesatChange()
                if fd._isProcessingOverride then return end
                if not fd._hideActiveOverriding then return end
                fd._isProcessingOverride = true
                local cdw = fd.cooldown
                local fc2 = _ecmeFC[frame]
                local sid2 = fc2 and fc2.spellID
                if sid2 and cdw then
                    if cdw.SetUseAuraDisplayTime then
                        cdw:SetUseAuraDisplayTime(false)
                    end
                    if cdw.SetCooldownFromDurationObject then
                        -- Resolve effective spell ID: when a spell is
                        -- transformed (e.g. Judgment -> Hammer of Wrath
                        -- under Wings), Blizzard's charge/cooldown APIs
                        -- report against the override ID, not the base.
                        -- Query the override first and fall back to the
                        -- base ID so non-transformed spells still work.
                        local effID = sid2
                        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                            local ovr = C_SpellBook.FindSpellOverrideByID(sid2)
                            if ovr and ovr > 0 and ovr ~= sid2 then
                                effID = ovr
                            end
                        end
                        local hasCharges = type(frame.HasVisualDataSource_Charges) == "function"
                            and frame:HasVisualDataSource_Charges()
                        local durObj
                        if hasCharges and C_Spell.GetSpellChargeDuration then
                            durObj = C_Spell.GetSpellChargeDuration(effID)
                            if not durObj and effID ~= sid2 then
                                durObj = C_Spell.GetSpellChargeDuration(sid2)
                            end
                        end
                        if not durObj and C_Spell.GetSpellCooldownDuration then
                            durObj = C_Spell.GetSpellCooldownDuration(effID)
                            if not durObj and effID ~= sid2 then
                                durObj = C_Spell.GetSpellCooldownDuration(sid2)
                            end
                        end
                        if durObj then
                            cdw:SetCooldownFromDurationObject(durObj)
                        end
                    end
                end
                fd.tex:SetDesaturated(true)
                fd._isProcessingOverride = false
            end
            hooksecurefunc(fd.tex, "SetDesaturated", onDesatChange)
            if fd.tex.SetDesaturation then
                hooksecurefunc(fd.tex, "SetDesaturation", onDesatChange)
            end
        end
        local isBuff = (barData.barType == "buffs" or barData.key == "buffs" or barData.barType == "custom_buff")
        fd.cooldown:SetReverse(isBuff)

        -- NOTE: Do NOT hook SetCooldown or Clear on the Cooldown widget.
        -- Hooking these runs our code inside Blizzard's secure cooldown update
        -- chain, which propagates taint to frame properties like isActive and
        -- allowAvailableAlert. Active state animations are handled during
        -- reanchor instead.
    end

    hookFrameData[frame] = fd
    return fd
end

-------------------------------------------------------------------------------
--  CategorizeFrame
-------------------------------------------------------------------------------
local function CategorizeFrame(frame, viewerBarKey)
    local displaySID, baseSID = ResolveFrameSpellID(frame)
    if not displaySID or displaySID <= 0 then return nil, nil, nil end

    -- Lazy route resolution: ResolveCDIDToBar handles cache lookup,
    -- diversion-set match, and viewer-default fallback (defaultBar =
    -- viewerBarKey, the viewer this frame came from). Always returns a
    -- valid bar key for any non-nil cdID.
    local cdID = frame.cooldownID
    local claimBarKey = ResolveCDIDToBar(cdID, viewerBarKey)
    if claimBarKey then
        local claimBD = barDataByKey[claimBarKey]
        local claimType = claimBD and claimBD.barType or claimBarKey
        local viewerIsBuff = (viewerBarKey == "buffs")
        local claimIsBuff  = (claimType == "buffs" or claimType == "custom_buff")
        if viewerIsBuff == claimIsBuff then
            return claimBarKey, displaySID, baseSID
        end
        -- Type mismatch (buff viewer routing to CD bar, or vice versa).
        -- Under the 1-spell-per-bar rule this can't happen via picker
        -- claims, but legacy data could trigger it. Fall through to the
        -- viewer's default bar so the frame still renders somewhere.
    end
    return viewerBarKey, displaySID, baseSID
end

-------------------------------------------------------------------------------
--  Trinket Frames
-------------------------------------------------------------------------------
local _trinketFrames = {}
ns._trinketFrames = _trinketFrames
local _trinketItemCache = { [13] = nil, [14] = nil }

local function GetOrCreateTrinketFrame(slotID)
    local f = _trinketFrames[slotID]
    if f then return f end

    f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(36, 36)
    f:Hide()
    f:EnableMouse(false)

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
    cd:EnableMouse(false)
    if cd.SetMouseClickEnabled then cd:SetMouseClickEnabled(false) end
    if cd.SetMouseMotionEnabled then cd:SetMouseMotionEnabled(false) end
    f.Cooldown = cd
    f._cooldown = cd

    f._isTrinketFrame = true
    f._trinketSlot = slotID
    f.cooldownID = nil
    f.cooldownInfo = nil
    f.layoutIndex = slotID == 13 and 99990 or 99991
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
        local locale = GetLocale()
        if locale == "enUS" or locale == "enGB" then
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
        else
            isRealOnUse = true
        end
    end
    f._trinketIsOnUse = isRealOnUse
end
ns.UpdateTrinketFrame = UpdateTrinketFrame

local function UpdateTrinketCooldown(slotID)
    local f = _trinketFrames[slotID]
    if not f or not f._trinketIsOnUse then return false end
    local start, dur, enable = GetInventoryItemCooldown("player", slotID)
    if start and dur and dur > 1.5 and enable == 1 then
        f._cooldown:SetCooldown(start, dur)
        if f._tex then f._tex:SetDesaturated(true) end
        return true
    else
        f._cooldown:Clear()
        if f._tex then f._tex:SetDesaturated(false) end
        return false
    end
end

local _trinketEventFrame = CreateFrame("Frame")
_trinketEventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
_trinketEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
_trinketEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
_trinketEventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_EQUIPMENT_CHANGED" then
        if arg1 == 13 or arg1 == 14 then
            UpdateTrinketFrame(arg1)
            if ns.QueueReanchor then ns.QueueReanchor() end
            local f = _trinketFrames[arg1]
            if f and f._trinketSpellID and not f._trinketIsOnUse then
                local slot = arg1
                C_Timer.After(1, function()
                    UpdateTrinketFrame(slot)
                    if ns.QueueReanchor then ns.QueueReanchor() end
                end)
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateTrinketFrame(13)
        UpdateTrinketFrame(14)
        -- Tooltip data may not be cached yet on login, causing on-use
        -- detection to fail. Retry only for trinkets that have a spell
        -- but weren't detected as on-use (tooltip wasn't ready).
        local needsRetry = false
        for _, slot in ipairs({13, 14}) do
            local f = _trinketFrames[slot]
            if f and f._trinketSpellID and not f._trinketIsOnUse then
                needsRetry = true
            end
        end
        if needsRetry then
            C_Timer.After(2, function()
                UpdateTrinketFrame(13)
                UpdateTrinketFrame(14)
                if ns.QueueReanchor then ns.QueueReanchor() end
            end)
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        for _, slot in ipairs({13, 14}) do
            if _trinketFrames[slot] and _trinketFrames[slot]._trinketIsOnUse then
                UpdateTrinketCooldown(slot)
            end
        end
    end
end)

-------------------------------------------------------------------------------
--  Desaturation curve for custom frames (taint-safe).
--  Step curve: 0 when no cooldown, 1 immediately when cooldown active.
--  EvaluateRemainingDuration on a DurationObject handles secret values
--  internally so we never compare secret numbers ourselves.
-------------------------------------------------------------------------------
local _desatCurve
if C_CurveUtil and C_CurveUtil.CreateCurve then
    _desatCurve = C_CurveUtil.CreateCurve()
    _desatCurve:SetType(Enum.LuaCurveType.Step)
    _desatCurve:AddPoint(0, 0)
    _desatCurve:AddPoint(0.001, 1)
end

local function ApplySpellDesaturation(f, durObj)
    if not f._tex then return end
    if durObj and _desatCurve and durObj.EvaluateRemainingDuration then
        local val = durObj:EvaluateRemainingDuration(_desatCurve, 0)
        f._tex:SetDesaturation(val or 0)
    else
        f._tex:SetDesaturation(0)
    end
end

-------------------------------------------------------------------------------
--  Preset/Custom Frames
-------------------------------------------------------------------------------
local _presetFrames = {}
ns._presetFrames = _presetFrames

local _racialCdListener = CreateFrame("Frame")
_racialCdListener:RegisterEvent("SPELL_UPDATE_COOLDOWN")
_racialCdListener:RegisterEvent("SPELL_UPDATE_CHARGES")
_racialCdListener:RegisterEvent("BAG_UPDATE_COOLDOWN")
_racialCdListener:SetScript("OnEvent", function()
    -- Directly update cooldowns on existing preset frames instead of
    -- waiting for CollectAndReanchor (which only runs on viewer changes).
    for fkey, f in pairs(_presetFrames) do
        if f:IsShown() then
            if (f._isRacialFrame or f._isCustomSpellFrame) and not f._isCustomBuffFrame then
                local sid = fkey:match(":(%d+)$")
                sid = sid and tonumber(sid)
                if sid then
                    local durObj = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(sid)
                    if durObj and f._cooldown and f._cooldown.SetCooldownFromDurationObject then
                        f._cooldown:SetCooldownFromDurationObject(durObj, true)
                    end
                    ApplySpellDesaturation(f, durObj)
                end
            elseif f._isItemPresetFrame and f._presetItemID then
                local itemID = f._presetItemID
                local getContainerCD = C_Container and C_Container.GetItemCooldown
                local start, dur
                if getContainerCD then
                    start, dur = getContainerCD(itemID)
                end
                if not (start and dur and dur > 1.5) then
                    start, dur = C_Item.GetItemCooldown(itemID)
                end
                if not (start and dur and dur > 1.5) and f._presetData and f._presetData.altItemIDs then
                    for _, altID in ipairs(f._presetData.altItemIDs) do
                        if getContainerCD then start, dur = getContainerCD(altID) end
                        if not (start and dur and dur > 1.5) then start, dur = C_Item.GetItemCooldown(altID) end
                        if start and dur and dur > 1.5 then break end
                    end
                end
                if start and dur and dur > 1.5 then
                    f._cooldown:SetCooldown(start, dur)
                    f._cdStart = start; f._cdDur = dur
                elseif not (f._cdStart and f._cdDur and GetTime() < f._cdStart + f._cdDur) then
                    f._cooldown:Clear()
                    f._cdStart = nil; f._cdDur = nil
                end
                -- Desaturate when on cooldown or zero count
                local itemOnCD = f._cdStart and f._cdDur and (GetTime() < f._cdStart + f._cdDur)
                local total = C_Item.GetItemCount(f._presetItemID) or 0
                if total == 0 and f._presetData and f._presetData.altItemIDs then
                    for _, altID in ipairs(f._presetData.altItemIDs) do
                        total = total + (C_Item.GetItemCount(altID) or 0)
                    end
                end
                local shouldDesat = (total == 0 or itemOnCD) and true or false
                if shouldDesat ~= f._lastDesat then
                    f._lastDesat = shouldDesat
                    if f._tex then f._tex:SetDesaturated(shouldDesat) end
                end
            end
        end
    end
    if QueueCustomBuffUpdate then QueueCustomBuffUpdate() end
end)

-- Custom aura bar cast detection
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

-------------------------------------------------------------------------------
--  Entry Pool + Sorting
-------------------------------------------------------------------------------
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

local _scratch_barLists  = {}   -- buff bars: barKey -> {entry, ...}
local _scratch_seenSpell = {}   -- buff bars: barKey -> {dedupKey -> true}
local _scratch_spellOrder = {}  -- CD/utility: spellID -> sort index
local _scratch_activeFrames = {}
local _scratch_usedFrames = {}
local _scratch_cdFrames = {}    -- CD/utility: barKey -> {frame, frame, ...}

local function _sortByLayoutIndex(a, b)
    return (a.layoutIndex or 0) < (b.layoutIndex or 0)
end
-- CD/utility sort: by sort order stored on the FC cache during collection.
-- Tiebreak by Blizzard's layoutIndex so frames with no user-defined order
-- (e.g. default bar with empty assignedSpells) render in Blizzard's natural
-- ordering instead of an unstable sort result.
local function _sortByCDOrder(a, b)
    local fcA = _ecmeFC[a]
    local fcB = _ecmeFC[b]
    local keyA = (fcA and fcA.sortOrder) or 99999
    local keyB = (fcB and fcB.sortOrder) or 99999
    if keyA ~= keyB then return keyA < keyB end
    local liA = a.layoutIndex or 99999
    local liB = b.layoutIndex or 99999
    return liA < liB
end

-------------------------------------------------------------------------------
--  CollectAndReanchor  (THE CORE)
--
--  1. EnumerateActive on all viewers
--  2. Route each frame to the correct bar
--  3. Filter by assignedSpells, inject custom frames
--  4. Decorate, sort, assign to icon slots, layout
--  5. Alpha 0 for unclaimed, alpha 1 for claimed
-------------------------------------------------------------------------------
local reanchorDirty = false
local reanchorFrame = nil
local viewerHooksInstalled = false

local function CollectAndReanchor()
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars or not p.cdmBars.enabled then return end

    if ns.RebuildCDMSpellCaches then ns.RebuildCDMSpellCaches() end

    -- Safety: if RebuildSpellRouteMap has never run successfully (API was
    -- unavailable during zone-in rebuild, e.g. fast arena transitions),
    -- attempt a fresh rebuild now. Test the build sentinel, NOT the
    -- diversion maps (which can legitimately be empty for users with no
    -- diversions) and NOT _cdidRouteMap (lazy cache, empty post-build).
    if not _routeMapBuilt and ns.RebuildSpellRouteMap then
        ns.RebuildSpellRouteMap()
    end

    wipe(_scratch_usedFrames)
    wipe(_scratch_activeFrames)
    local allActiveFrames = _scratch_activeFrames
    local usedFrames = _scratch_usedFrames

    -- Buff bars: existing entry-based collection (unchanged)
    local barLists = _scratch_barLists
    local seenSpell = _scratch_seenSpell
    for k, list in pairs(barLists) do ReleaseEntries(list) end
    for k, sub in pairs(seenSpell) do wipe(sub) end

    -- CD/utility bars: simple frame lists keyed by barKey
    local cdFrames = _scratch_cdFrames
    for k, list in pairs(cdFrames) do wipe(list) end

    local _FindOverride = C_SpellBook and C_SpellBook.FindSpellOverrideByID

    ---------------------------------------------------------------------------
    --  PHASE 1: Enumerate all viewers, split into buff vs CD/utility paths
    ---------------------------------------------------------------------------
    for viewerName, defaultBarKey in pairs(VIEWER_TO_BAR) do
        local viewer = _G[viewerName]
        if viewer and viewer.itemFramePool and viewer.itemFramePool.EnumerateActive then
            local isBuff = (defaultBarKey == "buffs")
            for frame in viewer.itemFramePool:EnumerateActive() do
                if IsFrameIncluded(frame) then
                    allActiveFrames[frame] = true

                    if isBuff then
                        -------------------------------------------------------
                        --  BUFF PATH (unchanged): CategorizeFrame + dedup
                        -------------------------------------------------------
                        if frame:IsShown() then
                            local targetBar, displaySID, baseSID = CategorizeFrame(frame, defaultBarKey)
                            if targetBar and displaySID and displaySID > 0 then
                                local barSeen = seenSpell[targetBar]
                                if not barSeen then barSeen = {}; seenSpell[targetBar] = barSeen end
                                local dedupKey = frame.cooldownID
                                if dedupKey and not barSeen[dedupKey] then
                                    if not barLists[targetBar] then barLists[targetBar] = {} end
                                    barLists[targetBar][#barLists[targetBar] + 1] =
                                        AcquireEntry(frame, displaySID, baseSID or displaySID, frame.layoutIndex or 0)
                                    barSeen[dedupKey] = true
                                end
                            end
                        end
                    else
                        -------------------------------------------------------
                        --  CD/UTILITY PATH: lazy resolve via ResolveCDIDToBar
                        --  Default bar = the viewer this frame came from.
                        -------------------------------------------------------
                        local cdID = frame.cooldownID
                        local barKey = ResolveCDIDToBar(cdID, defaultBarKey)
                        if barKey then
                            local bd = barDataByKey[barKey]
                            if bd and bd.barType ~= "buffs" and not bd.isGhostBar then
                                local displaySID, baseSID = ResolveFrameSpellID(frame)
                                if displaySID and displaySID > 0 then
                                    if not cdFrames[barKey] then cdFrames[barKey] = {} end
                                    local frames = cdFrames[barKey]
                                    frames[#frames + 1] = frame
                                    local fc = FC(frame)
                                    fc.barKey = barKey
                                    fc.spellID = baseSID or displaySID
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local LayoutCDMBar = ns.LayoutCDMBar
    local RefreshCDMIconAppearance = ns.RefreshCDMIconAppearance
    local ApplyCDMTooltipState = ns.ApplyCDMTooltipState

    ---------------------------------------------------------------------------
    --  PHASE 2: Process BUFF bars (existing flow, completely unchanged)
    ---------------------------------------------------------------------------
    for barKey, list in pairs(barLists) do
        local barData = barDataByKey[barKey]
        if barData and barData.enabled and barData.barType ~= "custom_buff" then
            local container = cdmBarFrames[barKey]
            if container then
                table.sort(list, _sortByLayoutIndex)

                local icons = cdmBarIcons[barKey]
                if not icons then icons = {}; cdmBarIcons[barKey] = icons end
                local count = 0

                local hideCD = not barData.showCooldownText
                for _, entry in ipairs(list) do
                    count = count + 1
                    local frame = entry.frame
                    usedFrames[frame] = true
                    DecorateFrame(frame, barData)
                    FC(frame).barKey = barKey
                    FC(frame).spellID = entry.baseSpellID or entry.spellID
                    icons[count] = frame
                    local barHidden = container and container._visHidden
                    frame:SetAlpha(barHidden and 0 or 1)
                    frame:Show()
                    if frame.Cooldown then
                        if frame.Cooldown.SetDrawSwipe then
                            frame.Cooldown:SetDrawSwipe(true)
                        end
                        frame.Cooldown:SetHideCountdownNumbers(hideCD)
                    end
                end

                -- Clear excess buff icons (Blizzard owns lifecycle, only disable swipe)
                for i = count + 1, #icons do
                    local icon = icons[i]
                    if icon then
                        local efd = hookFrameData[icon]
                        if efd then efd._cdmAnchor = nil end
                        if icon.Cooldown and icon.Cooldown.SetDrawSwipe then
                            icon.Cooldown:SetDrawSwipe(false)
                        end
                    end
                    icons[i] = nil
                end

                -- Mark unclaimed buff frames as used
                for _, entry in ipairs(list) do
                    if entry.frame and not usedFrames[entry.frame] then
                        usedFrames[entry.frame] = true
                    end
                end

                -- Conditional layout for buffs (existing iconsChanged detection)
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

    -- Clean up empty buff bars
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and ns.IsBarBuffFamily(bd)
           and not bd.isGhostBar and not barLists[bd.key] then
            local icons = cdmBarIcons[bd.key]
            if icons then
                for i = 1, #icons do
                    if icons[i] then
                        local efd = hookFrameData[icons[i]]
                        if efd then efd._cdmAnchor = nil end
                        if icons[i].Cooldown and icons[i].Cooldown.SetDrawSwipe then
                            icons[i].Cooldown:SetDrawSwipe(false)
                        end
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

    ---------------------------------------------------------------------------
    --  PHASE 3: Process CD/UTILITY bars (simplified flow)
    --  For each bar: inject custom frames, assign sort keys, sort, position.
    --  No allowSet, no entryBySpell, no dedup, no change detection.
    ---------------------------------------------------------------------------

    -- Ensure custom-frame-only CD/utility bars get processed
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and not bd.isGhostBar
           and bd.barType ~= "buffs" and bd.barType ~= "custom_buff"
           and bd.key ~= "buffs" and not cdFrames[bd.key] then
            local sd = ns.GetBarSpellData(bd.key)
            if sd and sd.assignedSpells and #sd.assignedSpells > 0 then
                cdFrames[bd.key] = {}
            end
        end
    end

    for barKey, frames in pairs(cdFrames) do
        local barData = barDataByKey[barKey]
        if barData and barData.enabled then
            local container = cdmBarFrames[barKey]
            if container then
                local sd = ns.GetBarSpellData(barKey)
                local spellList = sd and sd.assignedSpells

                -- Build spell order map for sorting (store all variants)
                local spellOrder = _scratch_spellOrder; wipe(spellOrder)
                if spellList then
                    local idx = 0
                    for _, sid in ipairs(spellList) do
                        if sid and sid ~= 0 then
                            idx = idx + 1
                            if not spellOrder[sid] then spellOrder[sid] = idx end
                            -- Forward: base -> current override
                            if _FindOverride then
                                local ovr = _FindOverride(sid)
                                if ovr and ovr > 0 and ovr ~= sid and not spellOrder[ovr] then
                                    spellOrder[ovr] = idx
                                end
                            end
                            -- Reverse: override -> base
                            if C_Spell and C_Spell.GetBaseSpell then
                                local base = C_Spell.GetBaseSpell(sid)
                                if base and base > 0 and base ~= sid and not spellOrder[base] then
                                    spellOrder[base] = idx
                                end
                            end
                        end
                    end
                end

                -- Inject custom frames (trinkets, items, racials)
                if spellList then
                    for _, sid in ipairs(spellList) do
                        if sid and (sid == -13 or sid == -14) then
                            -- Trinket
                            local slot = -sid
                            local tf = _trinketFrames[slot]
                            if not tf then tf = GetOrCreateTrinketFrame(slot) end
                            UpdateTrinketFrame(slot)
                            if _trinketItemCache[slot] and tf._trinketIsOnUse then
                                UpdateTrinketCooldown(slot)
                                frames[#frames + 1] = tf
                                local fc = FC(tf)
                                fc.barKey = barKey; fc.spellID = sid
                            else
                                tf:Hide()
                            end
                        elseif sid and sid <= -100 then
                            -- Item preset (potions, healthstone, etc.)
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
                                    f:EnableMouse(false)
                                    local tex = f:CreateTexture(nil, "ARTWORK")
                                    tex:SetAllPoints(); tex:SetTexture(icon)
                                    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                                    f.Icon = tex; f._tex = tex
                                    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
                                    cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetDrawBling(false)
                                    cd:SetHideCountdownNumbers(true)
                                    cd:EnableMouse(false)
                                    if cd.SetMouseClickEnabled then cd:SetMouseClickEnabled(false) end
                                    if cd.SetMouseMotionEnabled then cd:SetMouseMotionEnabled(false) end
                                    f.Cooldown = cd; f._cooldown = cd
                                    f._isItemPresetFrame = true
                                    f._presetItemID = itemID; f._presetData = preset
                                    f.cooldownID = nil; f.cooldownInfo = nil
                                    f.layoutIndex = 99999
                                    local countFS = f:CreateFontString(nil, "OVERLAY")
                                    countFS:SetFont(GetCDMFont(), 11, "OUTLINE")
                                    countFS:SetShadowOffset(0, 0)
                                    countFS:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 2)
                                    f._itemCountText = countFS
                                    _presetFrames[fkey] = f
                                end
                            end
                            if f then
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
                                    -- keep cached cooldown
                                else
                                    f._cooldown:Clear()
                                    f._cdStart = nil; f._cdDur = nil
                                end
                                local itemOnCD = f._cdStart and f._cdDur and (GetTime() < f._cdStart + f._cdDur)
                                local total = C_Item.GetItemCount(itemID) or 0
                                if f._presetData and f._presetData.altItemIDs then
                                    for _, altID in ipairs(f._presetData.altItemIDs) do
                                        total = total + (C_Item.GetItemCount(altID) or 0)
                                    end
                                end
                                if f._itemCountText then
                                    local showItemCount = barData.showItemCount ~= false
                                    if total > 1 and showItemCount then
                                        f._itemCountText:SetText(total)
                                        f._itemCountText:Show()
                                    else
                                        f._itemCountText:SetText("")
                                        f._itemCountText:Hide()
                                    end
                                end
                                local shouldDesat = (total == 0 or itemOnCD) and true or false
                                if f._tex then f._tex:SetDesaturated(shouldDesat) end
                                f._lastDesat = shouldDesat
                                frames[#frames + 1] = f
                                local fc = FC(f)
                                fc.barKey = barKey; fc.spellID = sid
                            end
                        elseif sid and sid > 0 then
                            -- Racial / custom spell (only if no Blizzard frame claimed it)
                            -- Transform-aware: check base, override, and exact match
                            local hasClaim = false
                            for _, f in ipairs(frames) do
                                local fc = _ecmeFC[f]
                                if fc then
                                    local fSid = fc.spellID
                                    if fSid == sid then
                                        hasClaim = true; break
                                    end
                                    if _FindOverride and sid > 0 then
                                        local ovr = _FindOverride(sid)
                                        if ovr and ovr > 0 and fSid == ovr then hasClaim = true; break end
                                    end
                                    if C_Spell and C_Spell.GetBaseSpell then
                                        local base = C_Spell.GetBaseSpell(sid)
                                        if base and base > 0 and fSid == base then hasClaim = true; break end
                                    end
                                end
                            end
                            if not hasClaim then
                                local isRacial = ns._myRacialsSet and ns._myRacialsSet[sid]
                                local isCustomSpell = sd and sd.customSpellIDs and sd.customSpellIDs[sid]
                                -- Phase 3 injects custom frames for spells that
                                -- are NOT in Blizzard's CDM category (user-added
                                -- racials, user-added customs). If a spell IS in
                                -- CDM, Blizzard's native frame is authoritative
                                -- and renders on its own bar; injecting here
                                -- would produce a ghost duplicate that the user
                                -- cannot remove from the live bar (the picker
                                -- only touches assignedSpells). Example: a
                                -- Dracthyr Evoker utility preset with Wing
                                -- Buffet in assignedSpells -- Blizzard already
                                -- tracks it in CDM, so we must not inject.
                                local isKnownInCDM = ns.IsSpellKnownInCDM and ns.IsSpellKnownInCDM(sid)
                                if isKnownInCDM then
                                    -- Leave it to Blizzard's native frame. Skip.
                                elseif not isRacial and not isCustomSpell then
                                    -- Unknown spell, skip
                                else
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
                                        cd:SetScript("OnCooldownDone", function()
                                            if f._tex then f._tex:SetDesaturation(0) end
                                        end)
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
                                        ApplySpellDesaturation(f, durObj)
                                        f._cdSet = true; f._racialCdDirty = false
                                    end
                                    frames[#frames + 1] = f
                                    local fc = FC(f)
                                    fc.barKey = barKey; fc.spellID = sid
                                end
                            end
                        end
                    end
                end

                -- Assign sort keys from spellOrder (transform-aware)
                for _, frame in ipairs(frames) do
                    local fc = _ecmeFC[frame]
                    local sid = fc and fc.spellID
                    local key = sid and spellOrder[sid]
                    -- Check cached baseSpellID (stable across transforms)
                    if not key and fc and fc.baseSpellID then
                        key = spellOrder[fc.baseSpellID]
                    end
                    if not key and sid and sid > 0 and _FindOverride then
                        local ovr = _FindOverride(sid)
                        if ovr and ovr > 0 then key = spellOrder[ovr] end
                    end
                    if not key and sid and sid > 0 and C_Spell and C_Spell.GetBaseSpell then
                        local base = C_Spell.GetBaseSpell(sid)
                        if base and base > 0 and base ~= sid then key = spellOrder[base] end
                    end
                    if fc then fc.sortOrder = key or 99999 end
                end

                -- Sort by user-defined order
                table.sort(frames, _sortByCDOrder)

                -- Assign to icon slots, decorate, show
                local icons = cdmBarIcons[barKey]
                if not icons then icons = {}; cdmBarIcons[barKey] = icons end
                local barHidden = container._visHidden

                local hideCDText = not barData.showCooldownText
                for i, frame in ipairs(frames) do
                    usedFrames[frame] = true
                    DecorateFrame(frame, barData)
                    icons[i] = frame
                    frame:SetAlpha(barHidden and 0 or 1)
                    frame:Show()
                    if frame.Cooldown then
                        if frame.Cooldown.SetDrawSwipe then
                            frame.Cooldown:SetDrawSwipe(true)
                        end
                        frame.Cooldown:SetHideCountdownNumbers(hideCDText)
                    end
                    -- Reparent custom frames to our container (never to Blizzard viewers)
                    -- and force click-through. Something in the Decorate /
                    -- Show / SetParent / Cooldown path re-enables mouse on
                    -- these frames despite our creation-time EnableMouse(false),
                    -- so we re-disable them defensively here (mirroring the
                    -- custom aura bar pattern at ~L1792).
                    if frame._isRacialFrame or frame._isTrinketFrame
                       or frame._isPresetFrame or frame._isItemPresetFrame
                       or frame._isCustomSpellFrame then
                        if frame:GetParent() ~= container then
                            frame:SetParent(container)
                        end
                        frame:EnableMouse(false)
                        if frame.EnableMouseClicks then frame:EnableMouseClicks(false) end
                        if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
                        if frame.Cooldown then
                            frame.Cooldown:EnableMouse(false)
                            if frame.Cooldown.SetMouseClickEnabled then
                                frame.Cooldown:SetMouseClickEnabled(false)
                            end
                            if frame.Cooldown.SetMouseMotionEnabled then
                                frame.Cooldown:SetMouseMotionEnabled(false)
                            end
                        end
                    end
                    -- Active state hooks handled in DecorateFrame (SetSwipeColor
                    -- hook on every frame, forces our color always).
                end

                -- Clear excess icons
                local newCount = #frames
                for i = newCount + 1, #icons do
                    if icons[i] then
                        local efd = hookFrameData[icons[i]]
                        if efd then efd._cdmAnchor = nil end
                        icons[i]:ClearAllPoints()
                        icons[i]:Hide()
                        if icons[i].Cooldown and icons[i].Cooldown.SetDrawSwipe then
                            icons[i].Cooldown:SetDrawSwipe(false)
                        end
                    end
                    icons[i] = nil
                end

                -- Change detection (mirrors Phase 2 buff bars): skip the
                -- expensive Refresh/Layout/Tooltip calls when the icon set
                -- is identical to the previous reanchor. During rotation
                -- spam, OnCooldownIDSet fires per spell cast and queues a
                -- reanchor at the 0.2s throttle; the vast majority of those
                -- reanchors produce the exact same icon list and don't
                -- need the full layout pipeline re-run.
                local prevCount = container._prevVisibleCount or 0
                local iconsChanged = newCount ~= prevCount
                if not iconsChanged and container._prevIconRefs then
                    for idx = 1, newCount do
                        if container._prevIconRefs[idx] ~= icons[idx] then
                            iconsChanged = true; break
                        end
                    end
                else
                    iconsChanged = true
                end
                if iconsChanged then
                    RefreshCDMIconAppearance(barKey)
                    LayoutCDMBar(barKey)
                    ApplyCDMTooltipState(barKey)
                    if not container._prevIconRefs then container._prevIconRefs = {} end
                    for idx = 1, newCount do container._prevIconRefs[idx] = icons[idx] end
                    for idx = newCount + 1, #container._prevIconRefs do
                        container._prevIconRefs[idx] = nil
                    end
                end
                container._prevVisibleCount = newCount
            end
        end
    end

    -- Clean up empty CD/utility bars
    for _, bd in ipairs(p.cdmBars.bars) do
        if bd.enabled and not bd.isGhostBar
           and bd.barType ~= "buffs" and bd.barType ~= "custom_buff"
           and bd.key ~= "buffs" and not cdFrames[bd.key] then
            local icons = cdmBarIcons[bd.key]
            if icons then
                for i = 1, #icons do
                    if icons[i] then
                        local efd = hookFrameData[icons[i]]
                        if efd then efd._cdmAnchor = nil end
                        icons[i]:ClearAllPoints()
                        icons[i]:Hide()
                        if icons[i].Cooldown and icons[i].Cooldown.SetDrawSwipe then
                            icons[i].Cooldown:SetDrawSwipe(false)
                        end
                    end
                    icons[i] = nil
                end
            end
            local container = cdmBarFrames[bd.key]
            if container and (container._prevVisibleCount or 0) > 0 then
                container._prevVisibleCount = 0
                LayoutCDMBar(bd.key)
            end
        end
    end

    -- Re-apply proc glows for any active procs (picks up per-spell settings)
    if ns.ScanExistingProcGlows then ns.ScanExistingProcGlows() end

    ---------------------------------------------------------------------------
    --  PHASE 4: Global cleanup for unclaimed frames
    --  Also protect any frame currently in cdmBarIcons (may be from a
    --  previous reanchor cycle but still visually active on a bar).
    ---------------------------------------------------------------------------
    for bk, icons in pairs(cdmBarIcons) do
        for ii = 1, #icons do
            if icons[ii] then usedFrames[icons[ii]] = true end
        end
    end
    local buffViewer = _G["BuffIconCooldownViewer"]
    local barViewer  = _G["BuffBarCooldownViewer"]
    for frame in pairs(allActiveFrames) do
        if usedFrames[frame] then
            -- Claimed: leave alone
        elseif frame._isRacialFrame or frame._isTrinketFrame
               or frame._isPresetFrame or frame._isItemPresetFrame
               or frame._isCustomSpellFrame then
            -- Custom frames: managed by their own systems
        else
            local efd = hookFrameData[frame]
            if efd then efd._cdmAnchor = nil end
            local vf = frame.viewerFrame
            if vf == barViewer then
                -- Bar viewer frame: skip entirely when using Blizzard tracked bars
                local pp = ECME.db and ECME.db.profile
                if pp and pp.cdmBars and pp.cdmBars.useBlizzardBuffBars then
                    -- Leave untouched so Blizzard's tracked bars work
                else
                    if frame.Cooldown and frame.Cooldown.SetDrawSwipe then
                        frame.Cooldown:SetDrawSwipe(false)
                    end
                end
            elseif vf == buffViewer then
                -- Buff icon frame: only disable swipe, touch nothing else
                if frame.Cooldown and frame.Cooldown.SetDrawSwipe then
                    frame.Cooldown:SetDrawSwipe(false)
                end
            else
                -- CD/utility frame: hide (unrouted or ghost-bar routed)
                frame:ClearAllPoints()
                frame:Hide()
                if frame.Cooldown and frame.Cooldown.SetDrawSwipe then
                    frame.Cooldown:SetDrawSwipe(false)
                end
            end
        end
    end

    -- Hide orphaned custom frames (trinkets, potions, racials, custom
    -- spells) that are no longer referenced by any bar. Custom frames are
    -- never added to allActiveFrames (that table only holds Blizzard viewer
    -- pool frames), so the main Phase 4 loop above cannot see them.
    --
    -- The common case this catches is a spec swap where the new spec has
    -- fewer custom items than the old spec. Phase 3's write loop overwrites
    -- cdmBarIcons[barKey][i] in place, silently losing the reference to the
    -- previous frame at that index without hiding it. The "clear excess"
    -- loop only handles trailing indices (i > #newFrames), so a custom
    -- frame that was at index 1 in the old list gets overwritten and leaks:
    -- it stays shown, still parented to the bar container, and its stale
    -- SetPoint anchor drifts with the container on the new spec's layout.
    --
    -- Trinket frames are the most obvious offender because _trinketFrames
    -- is persistent across spec swaps (unlike _presetFrames, which gets
    -- wiped in FullCDMRebuild). Preset frames are handled belt-and-
    -- suspenders here too: the spec-swap wipe hides them, but any other
    -- path that removes a preset from assignedSpells without going through
    -- FullCDMRebuild would leak without this sweep.
    --
    -- Custom BUFF frames (f._isCustomBuffFrame) are skipped: their
    -- lifecycle lives in UpdateCustomBuffBars on a separate ticker, and
    -- hiding them here would flicker against that ticker's next Show call.
    for _, tf in pairs(_trinketFrames) do
        if tf and not usedFrames[tf] then
            tf:ClearAllPoints()
            tf:Hide()
        end
    end
    for _, pf in pairs(_presetFrames) do
        if pf and not pf._isCustomBuffFrame and not usedFrames[pf] then
            pf:ClearAllPoints()
            pf:Hide()
        end
    end

    if not ns._initialReanchorDone then ns._initialReanchorDone = true end

    -- Per-spec migration: convert pre-refactor "assignedSpells as content
    -- filter" data into "ghost-bar diversion" data. Must run AFTER reanchor
    -- because it walks the live viewer pools, which only get populated by
    -- Blizzard's CDM after our init code runs. The first reanchor that
    -- completes for a spec is the earliest moment we can guarantee the
    -- pools have content.
    --
    -- Per-spec flag is checked inside the migration, so this call is a
    -- no-op for already-migrated specs. After a successful migration, we
    -- rebuild the route map (so the new ghost entries become diversions)
    -- and queue another reanchor (so the now-ghost-routed frames get
    -- moved out of the default bars).
    if ns.MigrateSpecToBarFilterModelV6 then
        local specKey = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
        local sa = EllesmereUIDB and EllesmereUIDB.spellAssignments
        local prof = sa and sa.specProfiles and specKey and sa.specProfiles[specKey]
        local needsMigration = prof and not prof._barFilterModelV6
        if needsMigration then
            local added = ns.MigrateSpecToBarFilterModelV6()
            if added and added > 0 then
                if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
                if ns.QueueReanchor then ns.QueueReanchor() end
            end
        end
    end

    -- Per-spec one-shot: fold legacy dormantSpells back into assignedSpells
    -- at their saved slot index. Under the new "assignedSpells is pure user
    -- intent" model, dormant entries are restored so spells the old
    -- reconcile system evicted (pet abilities, choice-node talents) return
    -- to the user's chosen position. Rebuild the route map afterward so
    -- the revived entries become diversions.
    if ns.MergeDormantSpellsIntoAssigned then
        local specKey2 = ns.GetActiveSpecKey and ns.GetActiveSpecKey()
        local sa2 = EllesmereUIDB and EllesmereUIDB.spellAssignments
        local prof2 = sa2 and sa2.specProfiles and specKey2 and sa2.specProfiles[specKey2]
        if prof2 and not prof2._dormantMerged then
            ns.MergeDormantSpellsIntoAssigned()
            if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
            if ns.QueueReanchor then ns.QueueReanchor() end
        end
    end

    if ns.RequestBarGlowUpdate then ns.RequestBarGlowUpdate() end

    -- Authoritative final layout pass. Set by CDMFinishSetup (login) and
    -- ProcessSpecChange (spec swap). Now that icons are populated and bar
    -- sizes are correct, propagate width/height matches with valid source
    -- sizes, then apply saved positions so anchored elements latch onto
    -- their now-positioned targets. Cleared so subsequent reanchors don't
    -- redundantly run the layout pass.
    if ns._pendingApplyOnReanchor then
        ns._pendingApplyOnReanchor = nil
        -- CDM is done populating icons; lift the rebuild gate so width
        -- matching can propagate against settled bar widths. Must happen
        -- BEFORE ApplyAllWidthHeightMatches so it isn't gated off.
        if EllesmereUI then EllesmereUI._cdmRebuilding = nil end
        if EllesmereUI.ApplyAllWidthHeightMatches then
            EllesmereUI.ApplyAllWidthHeightMatches()
        end
        if EllesmereUI._applySavedPositions then
            EllesmereUI._applySavedPositions()
        end
    else
        -- Routine reanchor (icon churn, mob death, etc.) -- still clear
        -- the gate so subsequent layout calls don't get stuck.
        if EllesmereUI then EllesmereUI._cdmRebuilding = nil end
    end
end
ns.CollectAndReanchor = CollectAndReanchor

-------------------------------------------------------------------------------
--  UpdateCustomBuffBars
--  Custom Aura bars use UNIT_SPELLCAST_SUCCEEDED to detect usage,
--  then show icon with hardcoded duration (reverse cooldown swipe).
-------------------------------------------------------------------------------
local _customAuraTimers = {}

local function UpdateCustomBuffBars()
    -- if CooldownViewerSettings and CooldownViewerSettings:IsShown() then return end
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
                                    f:EnableMouse(false)
                                    local tex = f:CreateTexture(nil, "ARTWORK")
                                    tex:SetAllPoints(); tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                                    f.Icon = tex; f._tex = tex
                                    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
                                    cd:SetAllPoints(); cd:SetDrawEdge(false); cd:SetDrawBling(false)
                                    cd:SetHideCountdownNumbers(not barData.showCooldownText)
                                    cd:SetReverse(true)
                                    f.Cooldown = cd; f._cooldown = cd
                                    f._isCustomSpellFrame = true
                                    f._isCustomBuffFrame = true
                                    f.cooldownID = nil; f.cooldownInfo = nil
                                    f.layoutIndex = 99999
                                    _presetFrames[fkey] = f
                                    cd:HookScript("OnCooldownDone", function()
                                        C_Timer.After(0, QueueCustomBuffUpdate)
                                    end)
                                    local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
                                    if spInfo and spInfo.iconID and f._tex then f._tex:SetTexture(spInfo.iconID) end
                                end
                                if isActive then
                                    f._cooldown:SetCooldown(timer.start, timer.duration)
                                else
                                    f._cooldown:Clear()
                                end
                                DecorateFrame(f, barData); f:Show()
                                f:EnableMouse(false)
                                if f.Cooldown and f.Cooldown.SetDrawSwipe then
                                    f.Cooldown:SetDrawSwipe(true)
                                end
                                count = count + 1
                                icons[count] = f
                            else
                                local fkey = barKey .. ":custombuff:" .. sid
                                local f = _presetFrames[fkey]
                                if f then f:Hide() end
                                if timer and not isActive then
                                    _customAuraTimers[timerKey] = nil
                                end
                            end
                        end
                    end
                end

                for i = count + 1, #icons do
                    if icons[i] then icons[i]:Hide() end
                    icons[i] = nil
                end

                -- Custom aura bars are display-only, never clickable
                container:EnableMouse(false)
                if container.EnableMouseClicks then container:EnableMouseClicks(false) end
                if container.EnableMouseMotion then pcall(container.EnableMouseMotion, container, false) end

                local prevCount = container._prevVisibleCount or 0
                if count ~= prevCount then
                    if RefreshCDMIconAppearance then RefreshCDMIconAppearance(barKey) end
                    if LayoutCDMBar then LayoutCDMBar(barKey) end
                end
                container._prevVisibleCount = count
            end
        end
    end
    wipe(_pendingCastIDs)
end
ns.UpdateCustomBuffBars = UpdateCustomBuffBars

function ns.UpdateCustomBuffAuraTracking() end

-------------------------------------------------------------------------------
--  Lightweight position re-snap: re-applies stored _cdmAnchor on all claimed
--  icons without re-enumerating viewers or re-categorizing frames.
--  Used by OnActiveStateChanged where Blizzard may move frames but the icon
--  list hasn't changed.
-------------------------------------------------------------------------------
local function ReapplyPositions()
    for barKey, icons in pairs(cdmBarIcons) do
        if icons then
            for i = 1, #icons do
                local frame = icons[i]
                if frame then
                    local fd = hookFrameData[frame]
                    local anchor = fd and fd._cdmAnchor
                    if anchor then
                        frame:ClearAllPoints()
                        frame:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Reanchor Queue
-------------------------------------------------------------------------------
local REANCHOR_THROTTLE = 0.2
local _lastReanchorTime = 0

local function QueueReanchor()
    -- Always queue, never drop. If a spec swap is in progress the
    -- ProcessReanchorQueue gate will hold the request until the flag
    -- clears, then the queued reanchor fires naturally.
    reanchorDirty = true
    if reanchorFrame then reanchorFrame:Show() end
end
ns.QueueReanchor = QueueReanchor

-- Cancel any pending queued reanchor. Used by FullCDMRebuild's spec swap
-- branch when it runs CollectAndReanchor directly -- without this, the
-- reanchor BuildAllCDMBars queued earlier in the same call would fire a
-- second time after the throttle expires.
local function ClearQueuedReanchor()
    reanchorDirty = false
end
ns.ClearQueuedReanchor = ClearQueuedReanchor

local function ProcessReanchorQueue(self)
    if not reanchorDirty then self:Hide(); return end
    local now = GetTime()
    if now - _lastReanchorTime < REANCHOR_THROTTLE then return end
    reanchorDirty = false
    _lastReanchorTime = now
    CollectAndReanchor()
end

-------------------------------------------------------------------------------
--  SetupViewerHooks (mixin hooks)
--
--  Hook strategy:
--    1. OnCooldownIDSet on all 4 Blizzard CDM mixins -> QueueReanchor
--    2. Pool Acquire on all viewers -> QueueReanchor
--    3. Viewer Layout -> QueueReanchor (catches frame removals)
--    4. Buff ticker (0.1s) for staleness + glow
-------------------------------------------------------------------------------
function ns.SetupViewerHooks()
    if viewerHooksInstalled then return end
    viewerHooksInstalled = true

    -- Reanchor queue frame
    reanchorFrame = CreateFrame("Frame")
    reanchorFrame:SetScript("OnUpdate", ProcessReanchorQueue)
    reanchorFrame:Hide()

    -- 1. Mixin hooks: detect spell changes on CDM frames.
    --    Reset frame spell cache so the next reanchor re-resolves the spellID
    --    (handles spell transforms like Avenging Crusader -> Crusader Strike).
    local function ResetFrameAndReanchor(frame)
        if frame then
            local fc = _ecmeFC[frame]
            if fc then
                fc.resolvedSid = nil
                fc.baseSpellID = nil
                fc.overrideSid = nil
                fc.cachedCdID = nil
            end
            -- Don't clear fd.decorated or _cdidRouteMap here.
            -- Decoration only needs to happen once per frame.
            -- The cdidRouteMap entry is still valid (cooldownID doesn't
            -- change on transforms, only the spell behind it changes).
            -- CategorizeFrame will re-resolve the spell via baseSID.
        end
        -- Spell-catalog invalidation is intentionally NOT done here.
        -- OnCooldownIDSet fires constantly during combat as Blizzard's pool
        -- recycles frames, but the CDM category sets themselves only change
        -- on talent/spec/login events -- which already invalidate the cache
        -- via FullCDMRebuild and ScheduleTalentRebuild. Marking dirty here
        -- caused a 1.67ms RebuildCDMSpellCaches spike on every reanchor
        -- during combat for no semantic gain.
        QueueReanchor()
    end
    if CooldownViewerBuffIconItemMixin and CooldownViewerBuffIconItemMixin.OnCooldownIDSet then
        hooksecurefunc(CooldownViewerBuffIconItemMixin, "OnCooldownIDSet", ResetFrameAndReanchor)
    end
    if CooldownViewerEssentialItemMixin and CooldownViewerEssentialItemMixin.OnCooldownIDSet then
        hooksecurefunc(CooldownViewerEssentialItemMixin, "OnCooldownIDSet", ResetFrameAndReanchor)
    end
    if CooldownViewerUtilityItemMixin and CooldownViewerUtilityItemMixin.OnCooldownIDSet then
        hooksecurefunc(CooldownViewerUtilityItemMixin, "OnCooldownIDSet", ResetFrameAndReanchor)
    end
    if CooldownViewerBuffBarItemMixin and CooldownViewerBuffBarItemMixin.OnCooldownIDSet then
        hooksecurefunc(CooldownViewerBuffBarItemMixin, "OnCooldownIDSet", function(frame)
            if ns.InvalidateTBBFrameCache then ns.InvalidateTBBFrameCache() end
            ResetFrameAndReanchor(frame)
        end)
    end

    -- 2. Pool acquire hooks: detect new frames + install per-frame hooks
    -- Track which frames have been hooked (weak-keyed, no taint)
    local _activeStateHooked = setmetatable({}, { __mode = "k" })
    local _activeStateReanchorPending = false

    local function InstallBuffFrameHooks(viewer)
        if not viewer or not viewer.itemFramePool then return end
        for frame in viewer.itemFramePool:EnumerateActive() do
            if not _activeStateHooked[frame] then
                _activeStateHooked[frame] = true
                -- Hook OnActiveStateChanged: Blizzard calls this when a buff
                -- becomes active/inactive. Run a full reanchor so new/removed
                -- icons get collected and centered. Batched via C_Timer to
                -- collapse the spam (fires many times per frame).
                if frame.OnActiveStateChanged then
                    hooksecurefunc(frame, "OnActiveStateChanged", function()
                        ReapplyPositions()
                        if _activeStateReanchorPending then return end
                        _activeStateReanchorPending = true
                        C_Timer.After(0, function()
                            _activeStateReanchorPending = false
                            CollectAndReanchor()
                        end)
                    end)
                end
            end
        end
    end

    for vi, vName in ipairs(VIEWER_NAMES) do
        local v = _G[vName]
        if v and v.itemFramePool then
            local isBuff = (vi == 3 or vi == 4) -- BuffIcon or BuffBar
            local isBarViewer = (vi == 4) -- BuffBarCooldownViewer
            hooksecurefunc(v.itemFramePool, "Acquire", function()
                if isBuff then InstallBuffFrameHooks(v) end
                if isBarViewer and ns.InvalidateTBBFrameCache then
                    ns.InvalidateTBBFrameCache()
                end
                QueueReanchor()
            end)
            -- Hook existing frames too
            if isBuff then InstallBuffFrameHooks(v) end

            -- Intercept newly acquired frames the instant Blizzard creates
            -- them, before they render at the viewer's default position.
            -- Alpha 0 until our reanchor claims and positions them.
            -- The pool Acquire hook above already queues a reanchor.
            -- Skip during init: on /reload ALL frames are acquired at once
            -- and our reanchor hasn't run yet, so blanking them would hide
            -- all buffs until the first buff change.
            if v.OnAcquireItemFrame then
                hooksecurefunc(v, "OnAcquireItemFrame", function(_, itemFrame)
                    if not ns._initialReanchorDone then return end
                    -- Skip blanking bar viewer children when user wants Blizzard tracked bars
                    if isBarViewer then
                        local pp = ECME.db and ECME.db.profile
                        if pp and pp.cdmBars and pp.cdmBars.useBlizzardBuffBars then return end
                    end
                    if itemFrame then
                        itemFrame:SetAlpha(0)
                        if itemFrame.Cooldown and itemFrame.Cooldown.SetDrawSwipe then
                            itemFrame.Cooldown:SetDrawSwipe(false)
                        end
                    end
                end)
            end
        end
    end

    -- 3. Viewer Layout hooks (Essential + Utility only).
    -- Buff viewers are dynamic and positioned per-frame by CollectAndReanchor;
    -- hooking Layout on them causes taint when Blizzard calls it internally.
    local SYNC_VIEWERS = {
        EssentialCooldownViewer = "cooldowns",
        UtilityCooldownViewer   = "utility",
    }
    for viewerName, barKey in pairs(SYNC_VIEWERS) do
        local viewer = _G[viewerName]
        if viewer then
            if viewer.RefreshLayout then
                hooksecurefunc(viewer, "RefreshLayout", function()
                    QueueReanchor()
                end)
            end
            -- Re-apply our icon positions immediately when Blizzard
            -- re-layouts so frames don't flash to Blizzard positions.
            -- Re-layout ALL bars (including custom bars that share this viewer).
            hooksecurefunc(viewer, "Layout", function()
                local LCB = ns.LayoutCDMBar
                if LCB then
                    for bk, icons in pairs(cdmBarIcons) do
                        if icons and #icons > 0 then
                            LCB(bk)
                        end
                    end
                end
            end)
            local function SyncViewerToBar()
                if InCombatLockdown() then return end
                local container = cdmBarFrames[barKey]
                if not container then return end
                viewer:ClearAllPoints()
                viewer:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
                viewer:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
            end
            hooksecurefunc(viewer, "Layout", SyncViewerToBar)
            hooksecurefunc(viewer, "SetPoint", function(_, _, relativeTo)
                if InCombatLockdown() then return end
                local container = cdmBarFrames[barKey]
                if relativeTo == container then return end
                SyncViewerToBar()
            end)
            SyncViewerToBar()
        end
    end

    -- 3b. Buff viewer RefreshLayout hooks: run an IMMEDIATE reanchor (not
    -- queued) so icons are repositioned before the frame renders. Without
    -- this, new buff icons flash at Blizzard's default viewer position for
    -- up to 0.2s until the throttled reanchor fires.
    local buffViewer = _G["BuffIconCooldownViewer"]
    if buffViewer and buffViewer.RefreshLayout then
        hooksecurefunc(buffViewer, "RefreshLayout", function()
            CollectAndReanchor()
        end)
    end
    local buffBarViewer = _G["BuffBarCooldownViewer"]
    if buffBarViewer and buffBarViewer.RefreshLayout then
        hooksecurefunc(buffBarViewer, "RefreshLayout", function()
            CollectAndReanchor()
        end)
    end

    -- 4. CooldownViewerSettings show/hide: force reanchor.
    -- When CDM settings panel closes, Blizzard may re-layout its viewers.
    -- Queue a reanchor to re-sync our bar positions.
    if EventRegistry and EventRegistry.RegisterCallback then
        local cdmSettingsOwner = {}
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnShow",
            QueueReanchor, cdmSettingsOwner)
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnHide", function()
            C_Timer.After(0.1, QueueReanchor)
        end, cdmSettingsOwner)
    end

    -- 4b. Delayed reanchor on load: catch frames created after initial setup.
    -- Some buff frames (e.g. Dread Plague) may not exist until Blizzard's
    -- viewer finishes its deferred layout pass. Also invalidate TBB cache
    -- so tracking bars re-scan for late-loading BuffBar viewer frames.
    local function DelayedFullRefresh()
        if ns.InvalidateTBBFrameCache then ns.InvalidateTBBFrameCache() end
        QueueReanchor()
    end
    C_Timer.After(1, DelayedFullRefresh)
    C_Timer.After(3, DelayedFullRefresh)
    C_Timer.After(6, DelayedFullRefresh)

    -- 5. Buff ticker: staleness check + buff/pandemic glow (0.1s)
    do
        local cdmBuffTickFrame = CreateFrame("Frame")
        local cdmBuffAccum = 0
        local _, _cachedClassToken = UnitClass("player")
        local _pandemicTickCache = {}
        cdmBuffTickFrame:SetScript("OnUpdate", function(_, elapsed)
            cdmBuffAccum = cdmBuffAccum + elapsed
            if cdmBuffAccum < 0.1 then return end
            cdmBuffAccum = 0
            MemSnap("BuffTicker")
            local p = ECME and ECME.db and ECME.db.profile
            if not p or not p.cdmBars or not p.cdmBars.bars then return end
            local needsReanchor = false
            wipe(_pandemicTickCache)
            for _, bd in ipairs(p.cdmBars.bars) do
                if bd.enabled then
                    local isBuff = (bd.barType == "buffs" or bd.key == "buffs" or bd.barType == "custom_buff")
                    local buffGlowType = isBuff and (bd.buffGlowType or 0) or 0
                    local pandemicOn = bd.pandemicGlow
                    local icons = cdmBarIcons[bd.key]
                    if icons then
                        for fi = 1, #icons do
                            local frame = icons[fi]
                            if frame and frame:IsShown() then
                                local fc = _ecmeFC[frame]
                                local sid = fc and fc.resolvedSid
                                local fd = hookFrameData[frame]

                                -- Buff glow
                                if buffGlowType > 0 and fd then
                                    if not fd.buffGlowActive then
                                        if not fd.buffGlowOverlay then
                                            local ov = CreateFrame("Frame", nil, frame)
                                            ov:SetAllPoints(frame)
                                            ov:SetFrameLevel(frame:GetFrameLevel() + 7)
                                            ov:EnableMouse(false)
                                            fd.buffGlowOverlay = ov
                                        end
                                        local cr, cg, cb = bd.buffGlowR or 1.0, bd.buffGlowG or 0.776, bd.buffGlowB or 0.376
                                        if bd.buffGlowClassColor and _cachedClassToken then
                                            local cc = RAID_CLASS_COLORS[_cachedClassToken]
                                            if cc then cr, cg, cb = cc.r, cc.g, cc.b end
                                        end
                                        fd.buffGlowOverlay:SetAlpha(1)
                                        ns.StartNativeGlow(fd.buffGlowOverlay, buffGlowType, cr, cg, cb)
                                        fd.buffGlowActive = true
                                    end
                                elseif fd and fd.buffGlowActive and fd.buffGlowOverlay then
                                    ns.StopNativeGlow(fd.buffGlowOverlay)
                                    fd.buffGlowActive = false
                                end

                                -- Pandemic glow
                                if pandemicOn and sid and sid > 0 and fd then
                                    -- Check player auras, child frame aura data
                                    -- (covers buffs on other units like Lifebloom),
                                    -- and Blizzard's native PandemicIcon
                                    local cached = _pandemicTickCache[sid]
                                    if cached == nil then
                                        cached = ns.IsInPandemicWindow(sid) and true or false
                                        _pandemicTickCache[sid] = cached
                                    end
                                    local inPandemic = cached
                                        or ns.IsInPandemicFromChild(frame)
                                        or (frame.PandemicIcon and frame.PandemicIcon:IsShown())
                                    if inPandemic then
                                        if not fd.pandemicGlowActive then
                                            if not fd.pandemicOverlay then
                                                local ov = CreateFrame("Frame", nil, frame)
                                                ov:SetAllPoints(frame)
                                                ov:SetFrameLevel(frame:GetFrameLevel() + 8)
                                                ov:EnableMouse(false)
                                                fd.pandemicOverlay = ov
                                            end
                                            local c = bd.pandemicGlowColor or { r = 1, g = 1, b = 0 }
                                            local style = bd.pandemicGlowStyle or 1
                                            local glowOpts = (style == 1) and {
                                                N      = bd.pandemicGlowLines or 8,
                                                th     = bd.pandemicGlowThickness or 2,
                                                period = bd.pandemicGlowSpeed or 4,
                                            } or nil
                                            fd.pandemicOverlay:SetAlpha(1)
                                            ns.StartNativeGlow(fd.pandemicOverlay, style, c.r or 1, c.g or 1, c.b or 0, glowOpts)
                                            fd.pandemicGlowActive = true
                                        end
                                    elseif fd.pandemicGlowActive and fd.pandemicOverlay then
                                        ns.StopNativeGlow(fd.pandemicOverlay)
                                        fd.pandemicGlowActive = false
                                    end
                                end

                                -- (Per-icon active state handled by hooks in DecorateFrame, not ticker)
                            end
                        end
                    end
                end
            end
            if needsReanchor then QueueReanchor() end
            -- Refresh aura active cache. This is the sole maintainer of
            -- _activeCache; bar glow overlays read from ns._tickBlizzActiveCache.
            -- Walk the live pools and mark any frame whose Blizzard-set
            -- wasSetFromAura/auraInstanceID indicates an active aura.
            -- Calls ResolveFrameSpellID (which has its own resolve cache)
            -- so BuffBarCooldownViewer frames -- which CollectAndReanchor
            -- never visits -- still get their fc populated for bar glow
            -- triggers on Tracked Bar spells (Divine Protection etc).
            do
                local ac = _activeCache
                wipe(ac)
                for vi = 1, 4 do
                    local vf = _G[VIEWER_NAMES[vi]]
                    if vf and vf.itemFramePool and vf.itemFramePool.EnumerateActive then
                        for frame in vf.itemFramePool:EnumerateActive() do
                            if frame.wasSetFromAura == true or frame.auraInstanceID ~= nil then
                                local sid, baseSID = ResolveFrameSpellID(frame)
                                if sid and sid > 0 then
                                    ac[sid] = true
                                    if baseSID and baseSID > 0 then ac[baseSID] = true end
                                    local fc = _ecmeFC[frame]
                                    local linked = fc and fc.linkedSpellIDs
                                    if linked then
                                        for li = 1, #linked do
                                            local lsid = linked[li]
                                            if lsid and lsid > 0 then ac[lsid] = true end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                if ns.UpdateOverlayVisuals then ns.UpdateOverlayVisuals() end
            end
            MemDelta("BuffTicker")
        end)
    end

    ns.SyncViewerToContainer = function() end

    -- CDM settings panel: reanchor when user finishes editing
    if CooldownViewerSettings then
        CooldownViewerSettings:HookScript("OnHide", function()
            C_Timer.After(0.3, QueueReanchor)
        end)
    end

    -- EUI options panel: reanchor on show/hide
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

    -- Edit Mode close: full rebuild to restore CDM after Blizzard repositioned viewers.
    -- FullCDMRebuild is combat-safe (only touches our own frames).
    do
        local emf = _G.EditModeManagerFrame
        if emf then
            hooksecurefunc(emf, "Hide", function()
                C_Timer.After(0.1, function()
                    if ns.FullCDMRebuild then ns.FullCDMRebuild("editmode_close") end
                end)
            end)
        end
    end

    -- Listen for EditMode layout updates: Blizzard resets viewer frame
    -- pools when applying a layout (happens on spec swap). Reanchor to
    -- recollect the new frames. No flag manipulation -- just reanchor.
    do
        local emEventFrame = CreateFrame("Frame")
        emEventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
        emEventFrame:SetScript("OnEvent", function()
            QueueReanchor()
        end)
    end

    -- Lock EditMode for CDM frames (prevent user changes, avoid taint)
    ns.SetupEditModeLock()

    -- Initial reanchor
    C_Timer.After(0.2, function()
        QueueReanchor()
        UpdateCustomBuffBars()
    end)
end

function ns.IsViewerHooked()
    return viewerHooksInstalled
end

-------------------------------------------------------------------------------
--  EditMode Lock
--  Prevents users from changing CDM viewer settings via EditMode.
--  Hides the settings dialog, disables dragging, shows a lock notice.
-------------------------------------------------------------------------------
local _editModeLockInstalled = false
local _editModeLockNoticeShown = false

local function IsCooldownViewerSystemFrame(frame)
    local cooldownSystem = Enum and Enum.EditModeSystem and Enum.EditModeSystem.CooldownViewer
    return cooldownSystem and frame and frame.system == cooldownSystem
end

-- Skip locking the BuffBarCooldownViewer when the user has enabled
-- "Use Blizzard CDM Bars" -- they want to drag/configure that frame in
-- Edit Mode themselves. All other CDM viewers stay locked because EUI
-- manages their position via icon-level anchoring.
local function ShouldLockViewer(frame)
    if frame == _G["BuffBarCooldownViewer"] then
        local p = ECME and ECME.db and ECME.db.profile
        if p and p.cdmBars and p.cdmBars.useBlizzardBuffBars then
            return false
        end
    end
    return true
end

local function ShowEditModeLockNotice()
    if not _editModeLockNoticeShown then
        print("|cff0cd29fEllesmereUI CDM:|r Cooldown Viewer settings are managed by EllesmereUI. Edit Mode changes are disabled.")
        _editModeLockNoticeShown = true
    end
end

local function LockCooldownViewerFrames()
    for _, vName in ipairs(VIEWER_NAMES) do
        local frame = _G[vName]
        if IsCooldownViewerSystemFrame(frame) and ShouldLockViewer(frame) then
            frame:SetMovable(false)
            local selection = frame.Selection
            if selection then
                selection:SetScript("OnDragStart", nil)
                selection:SetScript("OnDragStop", nil)
            end
        end
    end
end

function ns.SetupEditModeLock()
    if _editModeLockInstalled then return end

    local function TrySetup()
        local dialog = _G.EditModeSystemSettingsDialog
        if not (dialog and Enum and Enum.EditModeSystem) then
            return false
        end

        -- When EditMode tries to show the settings dialog for a CDM frame, hide it
        hooksecurefunc(dialog, "AttachToSystemFrame", function(dlg, systemFrame)
            if not IsCooldownViewerSystemFrame(systemFrame) then return end
            if not ShouldLockViewer(systemFrame) then return end
            dlg:Hide()
            ShowEditModeLockNotice()
        end)

        -- When a CDM frame is selected in EditMode, lock it
        for _, vName in ipairs(VIEWER_NAMES) do
            local frame = _G[vName]
            if IsCooldownViewerSystemFrame(frame) then
                hooksecurefunc(frame, "SelectSystem", function(sf)
                    if not ShouldLockViewer(sf) then return end
                    sf:SetMovable(false)
                    if dialog.attachedToSystem == sf then
                        dialog:Hide()
                    end
                    ShowEditModeLockNotice()
                end)

                hooksecurefunc(frame, "HighlightSystem", function() end)

                hooksecurefunc(frame, "ClearHighlight", function() end)
            end
        end

        _editModeLockInstalled = true
        LockCooldownViewerFrames()
        return true
    end

    if not TrySetup() then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode", function()
            TrySetup()
        end)
    end
end
