if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_HookPressMirror.lua
--
--  Mirror Key Presses.
--  Reads the earlier hook files through ns and ns._hookInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._hookInternals
-- EllesmereUICdmHooks.lua or an earlier hook file failed to load.
if not I or I.broken then return end
I.broken = true

local barDataByKey = ns.barDataByKey
local cdmBarIcons = ns.cdmBarIcons
local _ecmeFC = ns._ecmeFC
local GetTime = GetTime

-------------------------------------------------------------------------------
--  Mirror Key Presses  (per-bar: barData.pressMirror -- set in CDM Bars > Extras)
--
--  Show the action-button "pushed down" look on a CDM bar icon whenever you
--  press that ability's keybind, even while on cooldown. Hooks the
--  action-button key-down path (ActionButtonDown/MultiActionButtonDown), which
--  fires on the physical press regardless of cooldown or the cast-on-key-
--  down/up CVar. Pushed texture + colour are read live from the EllesmereUI
--  action bars settings, so the CDM press matches real buttons (falling back
--  to a border-cropped Blizzard depress texture if that module isn't present).
--  On a custom-shape bar the press is masked to the shape, so a hexagon icon
--  flashes a hexagon rather than the full square it sits in.
--  Per-frame data lives in an external weak-keyed table.
-------------------------------------------------------------------------------
-- Wrapped in an IIFE (instead of a plain do...end) so this block gets its own
-- 200-local budget instead of sharing the file's main-chunk budget -- avoids
-- "main function has more than 200 local variables" as more locals accumulate
-- elsewhere in this file over time.
;(function()
    local AB_MEDIA      = "Interface\\AddOns\\EllesmereUIActionBars\\Media\\"
    local AB_HIGHLIGHT  = { AB_MEDIA .. "highlight-2.png", AB_MEDIA .. "highlight-3.png", AB_MEDIA .. "highlight-4.png" }
    local DEPRESS_TEX   = "Interface\\Buttons\\UI-Quickslot-Depress"
    local DEPRESS_INSET = 0.14   -- crop the beveled border off the fallback texture
    local MIN_VISIBLE   = 0.05   -- floor so ultra-fast taps still show a press
    local MAX_HOLD      = 2.0    -- safety: never leave an icon stuck "pressed"

    local _pushOverlay = setmetatable({}, { __mode = "k" })  -- [icon] = overlay frame
    local _held  = {}   -- [buttonFrame] = { overlays = {..}, keys = {..}, t = GetTime() }
    local _heldN = 0
    local _poll  = ns.TakeShell()
    _poll:Hide()

    -- Read the action bars' pushed settings live so the CDM press matches them.
    local function GetABProfile()
        local L = EllesmereUI and EllesmereUI.Lite
        if not (L and L.GetAddon) then return nil end
        local ok, eab = pcall(L.GetAddon, "EllesmereUIActionBars", true)
        if ok and eab and eab.db then return eab.db.profile end
        return nil
    end

    -- Style tex to match the bars' pushed look. Returns false when pushed is set
    -- to "None" (so the CDM press mirrors that), "border" for border mode, true otherwise.
    local function StylePush(tex)
        local p = GetABProfile()
        if p then
            local pType = p.pushedTextureType or 2
            local c = p.pushedCustomColor or { r = 0.973, g = 0.839, b = 0.604 }
            local cr, cg, cb = c.r, c.g, c.b
            if p.pushedUseClassColor then
                local _, ct = UnitClass("player")
                if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then cr, cg, cb = cc.r, cc.g, cc.b end end
            end
            tex:SetTexCoord(0, 1, 0, 1)
            if p.useClassicStyle then
                -- Classic WoW UI action bars: the vanilla pushed slot, uncropped.
                tex:SetAtlas(nil)
                tex:SetTexture(DEPRESS_TEX)
                tex:SetVertexColor(1, 1, 1, 1); tex:SetAlpha(1)
                return true
            elseif p.useBlizzardStyle then
                -- The bars' own pressed art: the retail sheet on WoW Forever
                -- (EllesmereUI.StockAtlas) unless the bars wear its own look.
                if EllesmereUI.IS_FOREVER == true and p.useForeverStyle == true then
                    tex:SetAtlas("UI-HUD-ActionBar-IconFrame-Down", false)
                else
                    EllesmereUI.StockAtlas(tex, "UI-HUD-ActionBar-IconFrame-Down", false)
                end
                tex:SetVertexColor(1, 1, 1, 1); tex:SetAlpha(1)
                return true
            elseif pType == 6 then
                tex:SetAlpha(0); return false
            elseif pType == 5 then
                tex:SetAlpha(0)
                return "border", cr, cg, cb, p.pushedBorderSize or 4
            end
            tex:SetAlpha(1)
            if pType <= 3 then
                tex:SetAtlas(nil); tex:SetTexture(AB_HIGHLIGHT[pType] or AB_HIGHLIGHT[2]); tex:SetVertexColor(cr, cg, cb, 1)
            elseif pType == 4 then
                tex:SetColorTexture(cr, cg, cb, 0.35)
            end
            return true
        end
        -- Fallback: interior of the Blizzard depress texture (border cropped off).
        tex:SetAtlas(nil)
        tex:SetTexture(DEPRESS_TEX)
        tex:SetTexCoord(DEPRESS_INSET, 1 - DEPRESS_INSET, DEPRESS_INSET, 1 - DEPRESS_INSET)
        tex:SetVertexColor(1, 1, 1, 1); tex:SetAlpha(1)
        return true
    end

    local function EnsureBorderEdges(ov)
        if ov._borderEdges then return ov._borderEdges end
        local edges = {}
        for j = 1, 4 do
            local t = ov:CreateTexture(nil, "OVERLAY", nil, 2)
            t:SetColorTexture(1, 1, 1, 1)
            t:Hide()
            edges[j] = t
        end
        ov._borderEdges = edges
        return edges
    end

    -- Custom shape of a CDM icon (hexagon/circle/...), or nil for a square one.
    -- A square press drawn over a shaped icon spills past the shape, so the
    -- overlay has to follow it. We reuse the icon's own shapeMask -- masking is
    -- screen-space and the overlay covers the same rect -- exactly like the
    -- fake-active overlay does (ns.ApplyShapeToOverlay). none/cropped return
    -- nil: their icon art fills the frame rect, so a square press is correct.
    local function IconShape(icon)
        local ifc = _ecmeFC and _ecmeFC[icon]
        if not (ifc and ifc.shapeApplied and ifc.shapeMask) then return nil end
        local shape = ifc.shapeName
        if not shape or shape == "none" or shape == "cropped" then return nil end
        return shape, ifc.shapeMask
    end

    -- Ring art for "border" pushed mode on a shaped icon: four straight edges
    -- around a hexagon leave the corners hanging in space, so press-flash the
    -- shape's own border texture instead. Its thickness is baked into the art,
    -- so the bars' pushed border size doesn't apply -- colour still does.
    local function EnsureShapeRing(ov)
        if ov._shapeRing then return ov._shapeRing end
        local t = ov:CreateTexture(nil, "OVERLAY", nil, 2)
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
        t:Hide()
        ov._shapeRing = t
        return t
    end

    local function ShowPush(icon)
        local ov = _pushOverlay[icon]
        if not ov then
            ov = CreateFrame("Frame", nil, icon)
            ov:SetFrameLevel(icon:GetFrameLevel() + 15)  -- above icon + cooldown swipe
            ov:Hide()
            local tex = ov:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints(ov)
            ov._tex = tex
            _pushOverlay[icon] = ov
        end
        -- Re-sync the shape mask on every press: the shape can change or be
        -- cleared between presses, and a cleared shapeMask is emptied + hidden
        -- rather than destroyed -- left attached it would blank the overlay.
        -- A shape swap keeps the same mask object (re-textured), so it stays.
        local shape, mask = IconShape(icon)
        if ov._shapeMask and ov._shapeMask ~= mask then
            pcall(ov._tex.RemoveMaskTexture, ov._tex, ov._shapeMask)
            ov._shapeMask = nil
        end
        if mask and not ov._shapeMask then
            pcall(ov._tex.AddMaskTexture, ov._tex, mask)
            ov._shapeMask = mask
        end
        -- Blizzard Style: the flash rounds off with the icon's viewer mask.
        if ns.CdmBlizzIcons() then
            local bm = ns.CdmBlizzIconMask(icon)
            if bm and ov._blizzMask ~= bm then
                pcall(ov._tex.AddMaskTexture, ov._tex, bm)
                ov._blizzMask = bm
            end
        end
        local result, cr, cg, cb, bsz = StylePush(ov._tex)
        if not result then ov:Hide(); return nil end
        -- Shaped icons expand their icon texture past the frame (and expand the
        -- texcoords to match), so anchor to the frame itself -- the rect the
        -- shapeMask covers -- rather than to the oversized texture.
        local region = (shape and icon) or icon.Icon or icon
        ov:ClearAllPoints()
        ov:SetPoint("TOPLEFT", region, "TOPLEFT", 0, 0)
        ov:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 0, 0)
        local ringTex = shape and ns.CDM_SHAPE_BORDERS and ns.CDM_SHAPE_BORDERS[shape]
        if result == "border" and ringTex then
            ov._tex:Hide()
            if ov._borderEdges then for j = 1, 4 do ov._borderEdges[j]:Hide() end end
            local ring = EnsureShapeRing(ov)
            ring:SetTexture(ringTex)
            ring:SetVertexColor(cr, cg, cb, 1)
            ring:ClearAllPoints(); ring:SetAllPoints(ov)
            ring:Show()
        elseif result == "border" then
            ov._tex:Hide()
            if ov._shapeRing then ov._shapeRing:Hide() end
            local edges = EnsureBorderEdges(ov)
            for j = 1, 4 do edges[j]:SetVertexColor(cr, cg, cb, 1) end
            edges[1]:ClearAllPoints(); edges[1]:SetPoint("TOPLEFT", ov); edges[1]:SetPoint("TOPRIGHT", ov); edges[1]:SetHeight(bsz); edges[1]:Show()
            edges[2]:ClearAllPoints(); edges[2]:SetPoint("BOTTOMLEFT", ov); edges[2]:SetPoint("BOTTOMRIGHT", ov); edges[2]:SetHeight(bsz); edges[2]:Show()
            edges[3]:ClearAllPoints(); edges[3]:SetPoint("TOPLEFT", edges[1], "BOTTOMLEFT"); edges[3]:SetPoint("BOTTOMLEFT", edges[2], "TOPLEFT"); edges[3]:SetWidth(bsz); edges[3]:Show()
            edges[4]:ClearAllPoints(); edges[4]:SetPoint("TOPRIGHT", edges[1], "BOTTOMRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT", edges[2], "TOPRIGHT"); edges[4]:SetWidth(bsz); edges[4]:Show()
        else
            ov._tex:Show()
            if ov._borderEdges then for j = 1, 4 do ov._borderEdges[j]:Hide() end end
            if ov._shapeRing then ov._shapeRing:Hide() end
        end
        ov:Show()
        return ov
    end

    ---------------------------------------------------------------------------
    --  Spell matching (pressed button's spell vs. a CDM icon's spell)
    ---------------------------------------------------------------------------
    local GetOverrideSpell      = C_Spell and C_Spell.GetOverrideSpell
    local GetBaseSpell          = C_Spell and C_Spell.GetBaseSpell
    local FindSpellOverrideByID = C_SpellBook and C_SpellBook.FindSpellOverrideByID

    local function safeNum(fn, arg)
        if type(fn) ~= "function" then return nil end
        local ok, res = pcall(fn, arg)
        if ok and type(res) == "number" and res > 0 then return res end
    end

    -- Warlock Hellcaller hero talent "Wither" replaces Corruption (Affliction)
    -- or Immolate (Destruction) on the action bar, but Blizzard exposes no
    -- live per-spec signal for it: GetOverrideSpell/GetBaseSpell/
    -- FindBaseSpellByID/FindSpellOverrideByID(445468) only ever resolve to
    -- 172, the LEGACY Corruption id -- in BOTH specs, never reaching 146739
    -- (the MODERN id the Affliction Cooldown Viewer slot is actually stamped
    -- with) or 157736 (the modern Immolate id on Destruction). Field-confirmed
    -- live (2026-08): pressing Wither in either spec resolves natively to
    -- {445468, 172} only, and neither cooldownInfo.spellID/overrideSpellID
    -- nor linkedSpellIDs vary with the active talent either -- so there is
    -- nothing dynamic to learn here. Hardcoded as one mutually-matching
    -- family instead, the same pattern as COMMAND_DEMON_FAMILY above.
    local WITHER_FAMILY = {
        [445468]  = true, -- Wither (the castable button, both specs)
        [172]     = true, -- Corruption, legacy id (what the native override chain reports)
        [146739]  = true, -- Corruption, modern id (Affliction CDM slot identity)
        [157736]  = true, -- Immolate, modern id (Destruction CDM slot identity)
    }

    -- Adds every WITHER_FAMILY id to `t` (in place) if any id already in `t`
    -- is a member. No-op otherwise. Kept as a tiny generic hook (AddSpellFamilies)
    -- so a future hardcoded family can be added alongside this one without
    -- touching SpellIdSet/IconMatches again.
    local SPELL_FAMILIES = { WITHER_FAMILY }
    local function AddSpellFamilies(t)
        for f = 1, #SPELL_FAMILIES do
            local fam = SPELL_FAMILIES[f]
            local hit = false
            for id in pairs(t) do
                if fam[id] then hit = true; break end
            end
            if hit then
                for fid in pairs(fam) do t[fid] = true end
            end
        end
    end

    local function SpellIdSet(id)
        local t = { [id] = true }
        -- Fuzzy override/base-spell resolution only makes sense for real
        -- spellIDs. Item/equipment-slot presses resolve to the addon's own
        -- NEGATIVE markers (see IconSpellID below) and must match exactly.
        if type(id) == "number" and id > 0 then
            local a = safeNum(GetOverrideSpell, id);      if a then t[a] = true end
            local b = safeNum(GetBaseSpell, id);          if b then t[b] = true end
            local c = safeNum(FindBaseSpellByID, id);     if c then t[c] = true end
            local d = safeNum(FindSpellOverrideByID, id); if d then t[d] = true end
            AddSpellFamilies(t)
        end
        return t
    end

    local function IconMatches(pressedSet, iconSid)
        if pressedSet[iconSid] then return true end
        if type(iconSid) ~= "number" or iconSid <= 0 then return false end
        local a = safeNum(GetOverrideSpell, iconSid); if a and pressedSet[a] then return true end
        local b = safeNum(GetBaseSpell, iconSid);     if b and pressedSet[b] then return true end
        -- Same hardcoded-family fallback as SpellIdSet, walked from the icon side.
        local famSet = { [iconSid] = true }
        AddSpellFamilies(famSet)
        for nid in pairs(famSet) do
            if nid ~= iconSid and pressedSet[nid] then return true end
        end
        return false
    end

    -- A CDM icon's identity as stamped by the bar-build pass (fc.spellID).
    -- For an actual spell this IS its spellID; for the addon's own item/
    -- equipment-slot tracking it is instead a NEGATIVE marker: -itemID for
    -- an item preset (potions, healthstone, custom items, always <= -100),
    -- or -inventorySlotID for an equipment-slot entry (trinkets = -13/-14).
    -- See ns.SlotIDFromKey / the item-preset injection above. SlotIdentities
    -- below produces this same marker (among other candidates) for a
    -- pressed action/macro so it can compare equal here.
    local function IconSpellID(icon)
        local fc = _ecmeFC and _ecmeFC[icon]
        local sid = fc and fc.spellID
        if sid then return sid end
        local cdID = icon.cooldownID
        if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
            local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
            if info then return info.overrideSpellID or info.spellID end
        end
        return nil
    end

    ---------------------------------------------------------------------------
    --  Press / hold / release. Release is driven by polling IsKeyDown on the
    --  button's binding keys, floored by MIN_VISIBLE and capped by MAX_HOLD.
    ---------------------------------------------------------------------------
    local function ReleaseEntry(btn, entry)
        local ovs = entry.overlays
        for i = 1, #ovs do ovs[i]:Hide() end
        _held[btn] = nil
        _heldN = _heldN - 1
        if _heldN <= 0 then _heldN = 0; _poll:Hide() end
    end

    _poll:SetScript("OnUpdate", function()
        if _heldN == 0 then _poll:Hide(); return end
        local now = GetTime()
        for btn, entry in pairs(_held) do
            local elapsed = now - entry.t
            local done = false
            if elapsed >= MAX_HOLD then
                done = true
            elseif elapsed >= MIN_VISIBLE then
                local anyDown = false
                local keys = entry.keys
                if keys then
                    for i = 1, #keys do
                        if keys[i] and IsKeyDown(keys[i]) then anyDown = true; break end
                    end
                end
                if not anyDown then done = true end
            end
            if done then ReleaseEntry(btn, entry) end
        end
    end)

    -- Cached enable-flag so OnPress can gate in O(1) instead of looping every
    -- bar on each key press (the ActionButtonDown hook fires for all users).
    -- Recomputed only when the bar list is rebuilt (RefreshCdmPressMirrorFlag,
    -- called from the CDM bar-rebuild pass) or when the toggle changes.
    -- TEMP DIAGNOSTIC: /euipressdebug toggles chat prints of the pressed-id
    -- set and every pressMirror-enabled icon's resolved spellID + match
    -- result, to find exactly where Wither/Corruption/Immolate diverges.
    -- Safe to delete once the real mismatch is found and fixed.
    -- TEMP DIAGNOSTIC: /euicdmdump <barKey> prints every icon currently in
    -- that bar's list (cdmBarIcons), regardless of shown state, with its
    -- fc.spellID / isHostedBuff / resolvedSid / baseSpellID and IsShown().
    -- Lets us see whether a hosted-buff placeholder exists at all right now,
    -- without needing a keypress. Safe to delete once diagnosis is done.
    SLASH_EUICDMDUMP1 = "/euicdmdump"
    SlashCmdList["EUICDMDUMP"] = function(msg)
        local barKey = msg and msg:match("%S+")
        if not barKey then
            print("|cff33ff99[EUI CDMDump]|r usage: /euicdmdump <barKey>  (known bars below)")
            if barDataByKey then
                local names = {}
                for k in pairs(barDataByKey) do names[#names+1] = tostring(k) end
                print("|cff33ff99[EUI CDMDump]|r bars: "..table.concat(names, ", "))
            end
            return
        end
        local list = cdmBarIcons and cdmBarIcons[barKey]
        if not list then
            print("|cff33ff99[EUI CDMDump]|r no such bar in cdmBarIcons: "..barKey)
            return
        end
        print("|cff33ff99[EUI CDMDump]|r bar="..barKey.." count="..#list)
        for i = 1, #list do
            local icon = list[i]
            local fc = _ecmeFC and _ecmeFC[icon]
            local cdID = icon and icon.cooldownID
            local info = cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
                and C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
            local function nameOf(id)
                if not id or type(id) ~= "number" or id <= 0 then return "?" end
                local ok, si = pcall(C_Spell.GetSpellInfo, id)
                return (ok and si and si.name) and si.name or "?"
            end
            local liveSid = icon and icon.GetSpellID and icon:GetSpellID()
            if issecretvalue and issecretvalue(liveSid) then liveSid = "<secret>" end
            local linked = ""
            if info and info.linkedSpellIDs and #info.linkedSpellIDs > 0 then
                local parts = {}
                for j = 1, #info.linkedSpellIDs do
                    parts[#parts+1] = info.linkedSpellIDs[j].."("..nameOf(info.linkedSpellIDs[j])..")"
                end
                linked = table.concat(parts, "/")
            end
            print(string.format(
                "  [%d] shown=%s fc.spellID=%s(%s) isHostedBuff=%s cdID=%s | info.spellID=%s(%s) info.overrideSpellID=%s(%s) live:GetSpellID=%s linked=%s",
                i,
                tostring(icon and icon:IsShown()),
                tostring(fc and fc.spellID), nameOf(fc and fc.spellID),
                tostring(fc and fc.isHostedBuff),
                tostring(cdID),
                tostring(info and info.spellID), nameOf(info and info.spellID),
                tostring(info and info.overrideSpellID), nameOf(info and info.overrideSpellID),
                tostring(liveSid),
                (linked ~= "" and linked or "-")
            ))
        end
    end

    SLASH_EUIPRESSDEBUG1 = "/euipressdebug"
    SlashCmdList["EUIPRESSDEBUG"] = function()
        EUI_PRESSMIRROR_DEBUG = not EUI_PRESSMIRROR_DEBUG
        print("|cff33ff99[EUI PressMirror]|r debug "..(EUI_PRESSMIRROR_DEBUG and "ON" or "OFF"))
    end

    local _anyPressMirror = false
    local function RefreshCdmPressMirrorFlag()
        _anyPressMirror = false
        if not barDataByKey then return end
        for barKey, bd in pairs(barDataByKey) do
            if bd then
                if bd.pressMirror then
                    _anyPressMirror = true
                    return
                end
                -- Bar toggle is off, but a hosted buff/debuff -- or, on a real
                -- buff-family bar, any tracked buff/debuff -- can still force
                -- Mirror Key Presses on via its own per-icon override (that
                -- icon's cog -> Mirror Key Presses -> On).
                local list = cdmBarIcons and cdmBarIcons[barKey]
                if list then
                    for i = 1, #list do
                        local icon = list[i]
                        local fc = _ecmeFC and _ecmeFC[icon]
                        if fc and fc.spellID and ns.ResolveSpellSettings then
                            local ss = ns.ResolveSpellSettings(icon, fc.spellID, false, barKey)
                            if ss and ss.pressMirror == "on" then
                                _anyPressMirror = true
                                return
                            end
                        end
                    end
                end
            end
        end
    end
    ns.RefreshCdmPressMirrorFlag = RefreshCdmPressMirrorFlag
    RefreshCdmPressMirrorFlag()

    -- A tracked trinket icon can be identified TWO different ways depending
    -- on whether Blizzard's own Cooldown Viewer already claims that
    -- equipment slot natively:
    --   * Native-claimed slot: Blizzard's viewer renders it, and its
    --     cooldownInfo carries a REAL spellID (the item's on-use spell) --
    --     IconSpellID falls back to C_CooldownViewer...GetCooldownViewerCooldownInfo
    --     for that case, or fc.spellID may already be a real base/override
    --     spellID copied from it.
    --   * Not natively claimed: the addon renders its OWN injected trinket
    --     frame instead (see the "Native-first, injection-fallback" branch
    --     above), stamped with its own marker instead of a spellID:
    --     -itemID for a plain item preset, -inventorySlotID for an
    --     equipment-slot entry (trinket 1/2 = -13/-14).
    -- Which path is live can differ per user/session, so a pressed item
    -- macro is resolved to BOTH candidate identities and matched against
    -- either -- whichever the on-screen icon actually turns out to be keyed by.
    local function ItemUseSpellID(itemID)
        if not itemID or not (C_Item and C_Item.GetItemSpell) then return nil end
        local _, spellID = C_Item.GetItemSpell(itemID)
        return spellID
    end

    local function AddIdentity(out, v)
        if v then out[#out + 1] = v end
    end

    -- Warlock demon "special ability" spells (Axe Toss, Singe Magic, Spell
    -- Lock, Seduction, Devour Magic, ...) are all cast through the SAME pet
    -- action-bar button, whose icon texture swaps per demon but whose
    -- Cooldown Viewer tracking stays anchored to one umbrella spell,
    -- "Command Demon" (119898) -- confirmed live: the CDM icon kept
    -- spellID 119898 across every demon type tested. A macro resolving to
    -- the specific demon ability (via /cast line parsing) needs 119898
    -- added as a match candidate too, since that's what the tracked icon
    -- actually carries. Member IDs sourced from EllesmereUI_Kick.lua's
    -- WARLOCK interrupt list plus the other demon specials.
    local COMMAND_DEMON_SPELL = 119898
    local COMMAND_DEMON_FAMILY = {
        [19647]   = true,  -- Spell Lock (Felhunter)
        [89766]   = true,  -- Axe Toss (Felguard)
        [119910]  = true,
        [1276467] = true,
        [132409]  = true,
        [89808]   = true,  -- Singe Magic (Imp)
        [6358]    = true,  -- Seduction (Succubus)
        [19505]   = true,  -- Devour Magic (Voidwalker)
    }

    -- Adds a real spellID identity, plus its Command Demon umbrella spell
    -- when it's a member of that family. Use this (not raw AddIdentity) for
    -- any resolved spellID coming from parsing a macro/action, so the
    -- pet-ability case is covered without every call site needing to know about it.
    local function AddSpellIdentity(out, spellID)
        AddIdentity(out, spellID)
        if spellID and COMMAND_DEMON_FAMILY[spellID] then
            AddIdentity(out, COMMAND_DEMON_SPELL)
        end
    end

    -- Rank-variant items (potions with several item IDs that share the same
    -- display name across ranks/"Fleeting" versions, e.g. Light's Potential)
    -- are tracked on CDM bars under ONE primary itemID (ns.CDM_ITEM_PRESETS),
    -- with the rank variants listed as altItemIDs -- the icon's own marker is
    -- always -primaryItemID, never -altItemID, even while an alt rank is
    -- what's actually in the player's bags/what a macro's typed name
    -- resolves to. Maps any itemID (primary or alt) to its preset's primary.
    local function PresetPrimaryItemID(itemID)
        if not itemID or not ns.CDM_ITEM_PRESETS then return nil end
        for _, pr in ipairs(ns.CDM_ITEM_PRESETS) do
            if pr.itemID == itemID then return pr.itemID end
            if pr.altItemIDs then
                for _, alt in ipairs(pr.altItemIDs) do
                    if alt == itemID then return pr.itemID end
                end
            end
        end
        return nil
    end

    local function AddItemIdentities(out, itemID)
        AddIdentity(out, -itemID)
        local primaryID = PresetPrimaryItemID(itemID)
        if primaryID and primaryID ~= itemID then AddIdentity(out, -primaryID) end
        AddSpellIdentity(out, ItemUseSpellID(itemID))
    end

    local function AddEquipSlotIdentities(out, slotID)
        AddIdentity(out, -slotID)
        local itemID = GetInventoryItemID and GetInventoryItemID("player", slotID)
        if itemID then AddSpellIdentity(out, ItemUseSpellID(itemID)) end
    end

    -- Parses a single macro line's target(s), if any:
    --   /use 13                         -> "slot", 13
    --   /use |Hitem:12345:...|h[Name]|h|r -> "itemLink", 12345
    --   /use Light's Potential          -> "itemName", "Light's Potential"
    --   /cast [pet:Imp][] Singe Magic   -> "spellNames", {"Singe Magic"}
    --   /castsequence Foo, Bar          -> "spellNames", {"Foo", "Bar"}
    -- Blizzard's own action auto-detection (GetActionInfo's subType, and the
    -- GetMacroItem/GetMacroSpell fallbacks) only ever resolves ONE line's
    -- worth of target -- for a multi-item potion macro or a per-pet/per-
    -- target conditional ability macro, that's the wrong answer as often as
    -- it's right (it picks by simple heuristic, not by evaluating which
    -- condition is actually true), so every line is read and classified
    -- here instead and ALL of them become match candidates. Strips
    -- [conditional] blocks and leading whitespace; deliberately not a full
    -- macro-syntax parser -- only the shapes real macros actually use.
    local function MacroLineTargets(line)
        local rest = line:gsub("%[[^%]]*%]", "")   -- strip [conditional] blocks
        local cmd, arg = rest:match("^%s*/(%a+)!?%s*(.-)%s*$")
        if not cmd or arg == "" then return nil end
        cmd = cmd:lower()
        if cmd == "use" or cmd == "userandom" then
            local linkItemID = arg:match("|Hitem:(%d+)")
            if linkItemID then return "itemLink", tonumber(linkItemID) end
            local slotNum = tonumber(arg:match("^(%d+)$"))
            -- Only a slot ns actually tracks/names (1..17,19) counts --
            -- rejects stray bare numbers that aren't really an equipment slot.
            if slotNum and ns.INV_SLOT_NAMES and ns.INV_SLOT_NAMES[slotNum] then
                return "slot", slotNum
            end
            return "itemName", (arg:match('^"(.-)"$') or arg)
        elseif cmd == "cast" or cmd == "castsequence" then
            local names = {}
            for name in arg:gmatch("[^,]+") do
                name = name:match("^%s*(.-)%s*$")
                name = name:match('^"(.-)"$') or name
                if name ~= "" and name:lower() ~= "reset" and not name:match("^%d+$") then
                    names[#names + 1] = name
                end
            end
            return #names > 0 and "spellNames" or nil, names
        end
        return nil
    end

    -- Every candidate identity (spellID and/or marker) for the action/macro
    -- bound to an action-bar slot.
    local function SlotIdentities(slot)
        local out = {}
        if not slot then return out end
        if HasAction and not HasAction(slot) then return out end
        -- NOTE (Midnight): GetActionInfo is documented as usable only in the
        -- secure restricted environment. This runs from an insecure post-hook,
        -- so a future build could hand back nil/secret here and silently no-op
        -- the press mirror. Revisit via a secure route if that ever regresses.
        local actionType, id, subType = GetActionInfo(slot)
        if actionType == "spell" then
            AddSpellIdentity(out, id)
        elseif actionType == "item" then
            -- Plain item-slot action (not routed through a macro at all):
            -- id IS the itemID here, unambiguously.
            if id then AddItemIdentities(out, id) end
        elseif actionType == "macro" then
            if subType == "spell" then
                -- Blizzard quirk: for a macro whose single action is a
                -- spell, id IS the resolved spellID directly (not the
                -- macro index).
                AddSpellIdentity(out, id)
            else
                -- Every other case (subType == "item", subType == "pet", or
                -- no subType at all): `id` from GetActionInfo is NOT a
                -- reliable macro index here (verified live: it can point at
                -- a completely unrelated macro). GetActionText -> the
                -- macro's own NAME -> GetMacroIndexByName is the reliable path.
                local macroName = GetActionText(slot)
                local macroIndex = macroName and GetMacroIndexByName(macroName)
                if macroIndex and macroIndex > 0 then
                    -- GetMacroItem returns the item's NAME (a string), not a
                    -- numeric itemID, and only ever resolves ONE item even
                    -- when the macro has several /use lines (e.g. a potion
                    -- macro with two different consumables) -- still tried
                    -- first since it's cheap, but the body scan below is
                    -- what actually covers every /use line.
                    local itemName = GetMacroItem and GetMacroItem(macroIndex)
                    local itemID = itemName and C_Item and C_Item.GetItemInfoInstant
                        and select(1, C_Item.GetItemInfoInstant(itemName))
                    if itemID then AddItemIdentities(out, itemID) end

                    -- ALWAYS also scan every /use and /cast line in the
                    -- macro body, regardless of what GetMacroItem already
                    -- resolved above: a multi-item macro (several potions, a
                    -- trinket slot plus a named item, etc.) or a per-pet/
                    -- per-target conditional ability macro needs an identity
                    -- per line -- Blizzard's own auto-detection only ever
                    -- picks ONE by simple heuristic (not by evaluating which
                    -- condition is actually true), so every possible outcome
                    -- is added as a candidate rather than trusting just one.
                    local body = GetMacroBody and GetMacroBody(macroIndex)
                    local matchedAny = false
                    if body then
                        for line in body:gmatch("[^\r\n]+") do
                            local kind, val = MacroLineTargets(line)
                            if kind == "slot" then
                                AddEquipSlotIdentities(out, val)
                                matchedAny = true
                            elseif kind == "itemLink" then
                                AddItemIdentities(out, val)
                                matchedAny = true
                            elseif kind == "itemName" then
                                local nameItemID = C_Item and C_Item.GetItemInfoInstant
                                    and select(1, C_Item.GetItemInfoInstant(val))
                                if nameItemID then
                                    AddItemIdentities(out, nameItemID)
                                    matchedAny = true
                                end
                            elseif kind == "spellNames" then
                                for _, spellName in ipairs(val) do
                                    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellName)
                                    local spellID = info and info.spellID
                                    if spellID then
                                        AddSpellIdentity(out, spellID)
                                        matchedAny = true
                                    end
                                end
                            end
                        end
                    end
                    if not itemID and not matchedAny then
                        -- GetMacroSpell also returns the spell's NAME (a
                        -- string), not a numeric spellID -- same shape of bug
                        -- as GetMacroItem above. Matters for pure /cast
                        -- conditional macros where none of the per-line
                        -- parsing above matched anything.
                        local macroSpellName = GetMacroSpell(macroIndex)
                        local macroSpellID = macroSpellName and C_Spell and C_Spell.GetSpellInfo
                            and (C_Spell.GetSpellInfo(macroSpellName) or {}).spellID
                        AddSpellIdentity(out, macroSpellID)
                    end
                end
            end
        end
        return out
    end

    -- Base key of a (possibly modified) binding, e.g. "SHIFT-1" -> "1".
    local function BaseKey(binding)
        return binding and binding:match("[^%-]+$") or nil
    end

    local function OnPress(btn, bindCmd)
        if not btn or not _anyPressMirror then return end
        local slot = btn.action or (btn.GetAttribute and btn:GetAttribute("action"))
        local ids = SlotIdentities(slot)
        if #ids == 0 then
            if EUI_PRESSMIRROR_DEBUG then
                print("|cff33ff99[EUI PressMirror]|r slot="..tostring(slot).." -> no identities resolved")
            end
            return
        end

        local pressedSet = {}
        for i = 1, #ids do
            local s = SpellIdSet(ids[i])
            for k in pairs(s) do pressedSet[k] = true end
        end
        if EUI_PRESSMIRROR_DEBUG then
            local function nameOf(id)
                if not id or type(id) ~= "number" or id <= 0 then return "?" end
                local ok, si = pcall(C_Spell.GetSpellInfo, id)
                return (ok and si and si.name) and si.name or "?"
            end
            local idList, pressedList = {}, {}
            for i = 1, #ids do idList[#idList+1] = tostring(ids[i]).."("..nameOf(ids[i])..")" end
            for k in pairs(pressedSet) do pressedList[#pressedList+1] = tostring(k).."("..nameOf(k)..")" end
            print("|cff33ff99[EUI PressMirror]|r slot="..tostring(slot)
                .." rawIDs=["..table.concat(idList, ", ").."]"
                .." pressedSet=["..table.concat(pressedList, ", ").."]")
        end
        local overlays
        if cdmBarIcons then
            for barKey, list in pairs(cdmBarIcons) do
                local bd = barDataByKey and barDataByKey[barKey]
                if bd then
                    for i = 1, #list do
                        local icon = list[i]
                        if icon and icon:IsShown() then
                            local fc = _ecmeFC and _ecmeFC[icon]
                            -- Effective enable for THIS icon: its own Mirror Key Presses cog
                            -- (Default/On/Off) overrides the bar-wide toggle when set; with no
                            -- override, it just inherits the bar toggle.
                            local enabled = bd.pressMirror
                            if fc and fc.spellID and ns.ResolveSpellSettings then
                                local ss = ns.ResolveSpellSettings(icon, fc.spellID, false, barKey)
                                local override = ss and ss.pressMirror
                                if override == "on" then enabled = true
                                elseif override == "off" then enabled = false end
                            end
                            if enabled then
                                local isid = IconSpellID(icon)
                                local matched = isid and IconMatches(pressedSet, isid)
                                if EUI_PRESSMIRROR_DEBUG and isid then
                                    local nm = "?"
                                    if type(isid) == "number" and isid > 0 then
                                        local ok, si = pcall(C_Spell.GetSpellInfo, isid)
                                        nm = (ok and si and si.name) and si.name or "?"
                                    end
                                    print("|cff33ff99[EUI PressMirror]|r bar="..tostring(barKey)
                                        .." iconSpellID="..tostring(isid).."("..nm..")"
                                        .." matched="..tostring(matched and true or false))
                                end
                                if matched then
                                    local ov = ShowPush(icon)
                                    if ov then overlays = overlays or {}; overlays[#overlays + 1] = ov end
                                end
                            end
                        end
                    end
                end
            end
        end
        if not overlays then return end

        local keys
        if bindCmd then
            local k1, k2 = GetBindingKey(bindCmd)
            keys = { BaseKey(k1), BaseKey(k2) }
        end
        local entry = _held[btn]
        if entry then
            entry.overlays = overlays; entry.keys = keys; entry.t = GetTime()
        else
            _held[btn] = { overlays = overlays, keys = keys, t = GetTime() }
            _heldN = _heldN + 1
        end
        _poll:Show()
    end

    -- Public: clear active overlays (called from the CDM Bars > Extras toggle).
    function ns.ClearCdmPressPush()
        for _, entry in pairs(_held) do
            local ovs = entry.overlays
            for i = 1, #ovs do ovs[i]:Hide() end
        end
        wipe(_held); _heldN = 0; _poll:Hide()
        RefreshCdmPressMirrorFlag()
    end

    ---------------------------------------------------------------------------
    --  Non-keybind casts (click-cast addons: Clique, mouseover binds, etc.)
    --
    --  Click-casting addons bind a spell to a mouse CLICK on a unit frame via
    --  a secure macro attribute -- there is no action-bar slot and no
    --  ActionButtonDown/MultiActionButtonDown event involved at all, so the
    --  hooks below can never see a Soulstone cast off a mouseover-friendly
    --  click-cast bind. UNIT_SPELLCAST_SENT fires for the player on every
    --  successful cast attempt regardless of what triggered it (keybind,
    --  mouse click, another addon's macro), always carrying the real spellID
    --  as its last argument -- reusing the same matching/overlay pipeline as
    --  OnPress catches this case generically, not just Clique specifically.
    ---------------------------------------------------------------------------
    local function FlashSpellID(spellID)
        if not spellID or not _anyPressMirror then return end
        local pressedSet = SpellIdSet(spellID)
        local overlays
        if cdmBarIcons then
            for barKey, list in pairs(cdmBarIcons) do
                local bd = barDataByKey and barDataByKey[barKey]
                if bd then
                    for i = 1, #list do
                        local icon = list[i]
                        if icon and icon:IsShown() then
                            local fc = _ecmeFC and _ecmeFC[icon]
                            local enabled = bd.pressMirror
                            if fc and fc.spellID and ns.ResolveSpellSettings then
                                local ss = ns.ResolveSpellSettings(icon, fc.spellID, false, barKey)
                                local override = ss and ss.pressMirror
                                if override == "on" then enabled = true
                                elseif override == "off" then enabled = false end
                            end
                            if enabled then
                                local isid = IconSpellID(icon)
                                if isid and IconMatches(pressedSet, isid) then
                                    local ov = ShowPush(icon)
                                    if ov then overlays = overlays or {}; overlays[#overlays + 1] = ov end
                                end
                            end
                        end
                    end
                end
            end
        end
        if not overlays then return end
        -- No keybind to poll for release (this wasn't a physical key press),
        -- so entry.keys stays nil -- the existing poll loop already treats a
        -- nil-keys entry as "release as soon as MIN_VISIBLE elapses" (see
        -- ReleaseEntry/the OnUpdate loop above), giving a short fixed flash.
        -- A fresh table per call as the _held key avoids two overlapping
        -- click-casts stomping on each other's release timer.
        local sentinel = {}
        _held[sentinel] = { overlays = overlays, keys = nil, t = GetTime() }
        _heldN = _heldN + 1
        _poll:Show()
    end

    -- Click-routed keybinds (Bars 9/10, empower spells, custom paging) go
    -- through the button via SetOverrideBindingClick and never fire the native
    -- commands hooked below; the EAB PostClick hook publishes them here.
    -- PostClick runs after Blizzard's click handler returns, downstream of its
    -- protected item-use calls -- same taint posture as the native hooks.
    _G._EUI_OnActionButtonPress = function(btn, down, bindCmd)
        -- Down edge only: buttons register both edges, and in key-up mode the
        -- key is already released by the up click.
        if not down or not btn or not bindCmd or not _anyPressMirror then return end
        -- Keyboard evidence (a real mouse click must not mirror): a held
        -- binding key proves keyboard, but wheel binds are never IsKeyDown, so
        -- the cursor-rect test covers those. Only miss: a wheel bind pressed
        -- while the cursor rests on its own button.
        local k1, k2 = GetBindingKey(bindCmd)
        local b1, b2 = BaseKey(k1), BaseKey(k2)
        local keyHeld = (b1 and IsKeyDown(b1)) or (b2 and IsKeyDown(b2))
        if not keyHeld and btn.IsUnderMouse and btn:IsUnderMouse() then return end
        OnPress(btn, bindCmd)
    end

    ---------------------------------------------------------------------------
    --  Hook the action-button key-down path (fires on press, even on cooldown)
    ---------------------------------------------------------------------------
    local MULTIBAR_BINDING = {
        MultiBarBottomLeft  = "MULTIACTIONBAR1BUTTON",
        MultiBarBottomRight = "MULTIACTIONBAR2BUTTON",
        MultiBarRight       = "MULTIACTIONBAR3BUTTON",
        MultiBarLeft        = "MULTIACTIONBAR4BUTTON",
        MultiBar5           = "MULTIACTIONBAR5BUTTON",
        MultiBar6           = "MULTIACTIONBAR6BUTTON",
        MultiBar7           = "MULTIACTIONBAR7BUTTON",
    }

    local ev = ns.TakeShell()
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:SetScript("OnEvent", function()
        if type(ActionButtonDown) == "function" then
            hooksecurefunc("ActionButtonDown", function(id)
                local btn = (GetActionButtonForID and GetActionButtonForID(id)) or _G["ActionButton" .. id]
                OnPress(btn, "ACTIONBUTTON" .. id)
            end)
        end
        if type(MultiActionButtonDown) == "function" then
            hooksecurefunc("MultiActionButtonDown", function(barName, id)
                local prefix = MULTIBAR_BINDING[barName]
                OnPress(_G[barName .. "Button" .. id], prefix and (prefix .. id) or nil)
            end)
        end
    end)

    -- See "Non-keybind casts" above: catches click-cast addons (Clique,
    -- mouseover binds, etc.) that never touch an action-bar button at all.
    -- spellID is grabbed as the LAST event argument rather than by a fixed
    -- position, since UNIT_SPELLCAST_SENT's exact argument list has varied
    -- across client versions but always ends with the spellID.
    local castEv = ns.TakeShell()
    if castEv.RegisterUnitEvent then
        castEv:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    else
        castEv:RegisterEvent("UNIT_SPELLCAST_SENT")
    end
    castEv:SetScript("OnEvent", function(_, _, unit, ...)
        if unit ~= "player" then return end
        local n = select("#", ...)
        local spellID = select(n, ...)
        if type(spellID) == "number" then FlashSpellID(spellID) end
    end)
end)()
I.broken = false
