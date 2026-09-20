if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EllesmereUI_DisableAutoAddSpells.lua
--
--  Optional behavior (off by default): stops Blizzard from auto-adding newly
--  learned/talented spells onto the main action bar, and suppresses the
--  "icon flies onto the bar" intro animation that goes with it.
--
--  Toggle: "Disable Auto-Add Spells" on the BLIZZARD POPUPS & GAME MENU page
--  (see EUI_BlizzardSkin_Options.lua). Saved as EllesmereUIDB.disableAutoAddSpells.
--  Changing it requires a UI reload, since IconIntroTracker's original
--  RegisterEvent method isn't preserved once overwritten.
--------------------------------------------------------------------------------

local function FeatureEnabled()
    return EllesmereUIDB and EllesmereUIDB.disableAutoAddSpells
end

-- Spells that legitimately belong on the bar the moment they're granted;
-- never strip these back off even with the feature enabled.
local ignoreList = {
    -- Dragonriding
    [372608] = true,
    [372610] = true,
    [361584] = true,
    [374990] = true,
    -- Dracthyr Soar abilities
    [376744] = true,
    [376743] = true,
}

-- Suppresses the icon-flies-onto-the-actionbar intro animation. Blizzard's
-- IconIntroTracker has no public "disable" API, so this neuters its event
-- handling directly; there's no way to hand the original method back once
-- overwritten, which is why the option requires a reload to turn off.
local function SuppressIconIntro()
    if not IconIntroTracker then return end
    IconIntroTracker.RegisterEvent = function() end
    IconIntroTracker:UnregisterEvent("SPELL_PUSHED_TO_ACTIONBAR")
end

-- Undoes an auto-add that slips through while a different action bar page is
-- showing (e.g. right after a talent swap put a new spell on a page you
-- weren't looking at).
local f = CreateFrame("Frame")
f:RegisterEvent("SPELL_PUSHED_TO_ACTIONBAR")
f:SetScript("OnEvent", function(self, event, spellID, slotIndex, slotPos)
    if not FeatureEnabled() then return end
    -- This event should never fire in combat, but check anyway.
    if InCombatLockdown() or ignoreList[spellID] then return end
    ClearCursor()
    PickupAction(slotIndex)
    ClearCursor()
end)

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if FeatureEnabled() then
        SuppressIconIntro()
    end
end)
