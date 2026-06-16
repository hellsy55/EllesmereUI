--------------------------------------------------------------------------------
--  EllesmereUI_Kick.lua
--  Shared interrupt spell lookup and cast-bar tint helpers for nameplates
--  and unit frames.
--------------------------------------------------------------------------------

local kickSpellsByClass = {
    DEATHKNIGHT = { 47528 },
    WARRIOR = { 6552 },
    WARLOCK = { 19647, 89766, 119910, 1276467, 132409 },
    SHAMAN = { 57994 },
    ROGUE = { 1766 },
    PRIEST = { 15487 },
    PALADIN = { 31935, 96231 },
    MONK = { 116705 },
    MAGE = { 2139 },
    HUNTER = { 187707, 147362 },
    EVOKER = { 351338 },
    DRUID = { 38675, 78675, 106839 },
    DEMONHUNTER = { 183752 },
}

local activeKickSpell

local function RefreshKickAbility()
    local playerClass = UnitClassBase("player")
    local classKicks = kickSpellsByClass[playerClass]
    activeKickSpell = nil
    if not classKicks then return end
    for i = 1, #classKicks do
        local spellId = classKicks[i]
        if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
            local known = C_SpellBook.IsSpellKnownOrInSpellBook(spellId)
            local petKnown = Enum and Enum.SpellBookSpellBank
                and C_SpellBook.IsSpellKnownOrInSpellBook(spellId, Enum.SpellBookSpellBank.Pet)
            if known or petKnown then
                activeKickSpell = spellId
            end
        elseif IsSpellKnown and IsSpellKnown(spellId) then
            activeKickSpell = spellId
        end
    end
end

local function ComputeCastBarTint(readyTint, baseTint)
    if not activeKickSpell then
        return baseTint.r, baseTint.g, baseTint.b
    end
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        return baseTint.r, baseTint.g, baseTint.b
    end
    if not (C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean) then
        return baseTint.r, baseTint.g, baseTint.b
    end
    local cdTime = C_Spell.GetSpellCooldownDuration(activeKickSpell)
    if not (cdTime and cdTime.IsZero) then
        return baseTint.r, baseTint.g, baseTint.b
    end
    local offCooldown = cdTime:IsZero()
    local rVal = C_CurveUtil.EvaluateColorValueFromBoolean(offCooldown, baseTint.r, readyTint.r)
    local gVal = C_CurveUtil.EvaluateColorValueFromBoolean(offCooldown, baseTint.g, readyTint.g)
    local bVal = C_CurveUtil.EvaluateColorValueFromBoolean(offCooldown, baseTint.b, readyTint.b)
    return rVal, gVal, bVal
end

EllesmereUI = EllesmereUI or {}
EllesmereUI.GetActiveKickSpell = function()
    return activeKickSpell
end
EllesmereUI.RefreshKickAbility = RefreshKickAbility
EllesmereUI.ComputeCastBarTint = ComputeCastBarTint

-- Unit context-menu fallback.
-- 12.0.7 added a gate to the secure SecureUnitButton_OnClick handler: a
-- "menu"/"togglemenu" click is dropped when C_ClickBindings.GetBindingType(button)
-- returns None -- always the case for EllesmereUI click-cast bindings, since we
-- register no C_ClickBindings. That silently kills the unit context menu for EVERY
-- key/mouse binding routed through our SecureUnitButton frames (12.0.5 has no gate,
-- so it works there). This insecure OnClick POST-HOOK (installed via HookScript,
-- never SetScript) re-opens the menu in Lua and never touches any other action -- it
-- bails unless the click's effective action is the menu. It installs on all client
-- versions: on 12.0.7+ it is the only thing that opens the menu; on 12.0.5 the secure
-- menu still fires too, but the menu manager simply re-opens it (the redundant build
-- is invisible on a click-rate action), so there is no harmful double-open.
function EllesmereUI.OpenUnitMenuFallback(self, button)
    if not (SecureButton_GetModifiedAttribute and C_ClickBindings and C_ClickBindings.GetBindingType
            and Enum and Enum.ClickBindingType and UnitPopup_OpenMenu) then
        return
    end
    -- Resolve the SAME effective action the secure handler used for this exact
    -- button (honors modifiers and the *type wildcard), so a spell/macro bind on
    -- any button -- type "spell"/"macro" -- is never intercepted. Only the bare
    -- context menu proceeds.
    local action = SecureButton_GetModifiedAttribute(self, "type", button)
    if action ~= "menu" and action ~= "togglemenu" then return end
    local mods = (C_ClickBindings.MakeModifiers and C_ClickBindings.MakeModifiers())
              or (MakeModifiers and MakeModifiers()) or 0
    -- Only step in when the secure menu was suppressed (gated). If it still fires
    -- (binding type ~= None) we do nothing, so there is never a double-open.
    if C_ClickBindings.GetBindingType(button, mods) ~= Enum.ClickBindingType.None then return end
    local unit = (SecureButton_GetModifiedUnit and SecureButton_GetModifiedUnit(self, button))
              or self:GetAttribute("unit")
    if not unit then return end
    if issecretvalue and issecretvalue(unit) then return end
    if not UnitExists(unit) then return end
    -- Resolve the menu type the same way the secure togglemenu action does.
    local lu = string.lower(unit)
    local utype = string.match(lu, "^([a-z]+)%d+$") or lu
    local which
    if utype == "party" then which = "PARTY"
    elseif utype == "raid" then which = "RAID_PLAYER"
    elseif utype == "boss" then which = "BOSS"
    elseif utype == "focus" then which = "FOCUS"
    elseif utype == "arena" or utype == "arenapet" then which = "ARENAENEMY"
    elseif UnitIsUnit(lu, "player") then which = "SELF"
    elseif UnitIsUnit(lu, "vehicle") then which = "VEHICLE"
    elseif UnitIsUnit(lu, "pet") then which = "PET"
    elseif UnitIsPlayer(lu) then
        if UnitInRaid(lu) then which = "RAID_PLAYER"
        elseif UnitInParty(lu) then which = "PARTY"
        else which = "PLAYER" end
    else which = "TARGET" end
    pcall(UnitPopup_OpenMenu, which, { unit = lu })
end

local kickFrame = CreateFrame("Frame")
kickFrame:RegisterEvent("PLAYER_LOGIN")
kickFrame:RegisterEvent("SPELLS_CHANGED")
kickFrame:SetScript("OnEvent", function()
    RefreshKickAbility()
end)

if UnitGUID("player") then
    RefreshKickAbility()
end
