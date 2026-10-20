if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- Nameplate Auto-enable. All categories are opt-in. Environment rules own
-- only the associated CVars; combat rules win for visibility and Show All.
-- The EUI manual preferences remain intact and are restored on hand-back.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._npInternals
if not I or I.broken then return end
I.broken = true

local defaults = {
    combat = { enabled = false,
        enemyCombat = true, enemyOOC = true, friendlyCombat = true, friendlyOOC = true,
        healthCombat = false, healthOOC = false, alwaysCombat = true, alwaysOOC = true },
    raidParty = { enabled = false, pets = true, totems = true },
    friendly = { enabled = false, party = false, raid = false, arena = true, cities = true, world = false },
    enemy = { enabled = false, party = true, raid = true, arena = true, cities = true, world = true },
    stacking = { enabled = false, party = true, raid = true, arena = true, cities = true, world = true },
    always = { enabled = false, party = true, raid = true, arena = true, cities = true, world = true },
}
ns.NP_AutoDefaults = defaults
local owned = {}
local stackingOwned

local function Profile()
    return I.ENP and I.ENP.db and I.ENP.db.profile
end
local function Value(category, option)
    local p = Profile()
    local t = p and p.autoEnable and p.autoEnable[category]
    local v = t and t[option]
    if v == nil then return defaults[category][option] end
    return v == true
end
ns.NP_AutoValue = Value
function ns.NP_AutoSet(category, option, value)
    local p = Profile()
    if not p or not defaults[category] or defaults[category][option] == nil then return end
    if not p.autoEnable then p.autoEnable = {} end
    if not p.autoEnable[category] then p.autoEnable[category] = {} end
    p.autoEnable[category][option] = value == true
    ns.ApplyAutoNameplates()
end

function ns.NP_AutoRaidPetOverride()
    if not Value("raidParty", "enabled") or not Value("raidParty", "pets") then return false end
    local _, kind, difficulty = GetInstanceInfo()
    return kind == "party" or kind == "raid" or difficulty == 208
end

function ns.AutoNameplatesOwnsEnemy()
    return Value("combat", "enabled") or Value("enemy", "enabled")
end

local function Area()
    local _, kind, difficulty = GetInstanceInfo()
    if difficulty == 208 then kind = "party" end
    if kind == "party" or kind == "raid" then return kind end
    if kind == "arena" or kind == "pvp" then return "arena" end
    return IsResting() and "cities" or "world"
end

local function Write(name, value)
    if value == nil then return end
    local want = value and "1" or "0"
    local current = GetCVar(name)
    if current == nil then return end
    if owned[name] == nil then owned[name] = current end
    if current ~= want then pcall(EllesmereUI.SetCVar, name, want, "EllesmereUINameplates") end
end

local function Restore(name, fallback)
    local before = owned[name]
    if before == nil then return end
    owned[name] = nil
    if fallback ~= nil then before = fallback end
    if GetCVar(name) ~= before then
        pcall(EllesmereUI.SetCVar, name, before, "EllesmereUINameplates")
    end
end

function ns.ApplyAutoNameplates()
    local p = Profile()
    if not p then return end
    local area = Area()
    local combat = InCombatLockdown() == true
    local mode = combat and "Combat" or "OOC"
    local desired = {}
    local friendlyCvar = GetCVar("nameplateShowFriendlyPlayers") ~= nil
        and "nameplateShowFriendlyPlayers" or "nameplateShowFriends"

    if Value("combat", "enabled") then
        desired.nameplateShowEnemies = Value("combat", "enemy" .. mode)
        desired[friendlyCvar] = Value("combat", "friendly" .. mode)
        desired.nameplateShowAll = Value("combat", "always" .. mode)
        desired.nameplateShowOnlyNameForFriendlyPlayerUnits = Value("combat", "health" .. mode)
    else
        if Value("enemy", "enabled") then desired.nameplateShowEnemies = Value("enemy", area) end
        if Value("friendly", "enabled") then desired[friendlyCvar] = Value("friendly", area) end
        if Value("always", "enabled") then desired.nameplateShowAll = Value("always", area) end
    end
    -- The raid/party special case is deliberately additive: no pet/totem
    -- override outside instances, and the ordinary EUI pet preference wins.
    if (area == "party" or area == "raid") and Value("raidParty", "enabled") then
        if Value("raidParty", "pets") then desired.nameplateShowEnemyPets = false end
        if Value("raidParty", "totems") then desired.nameplateShowEnemyTotems = false end
    end

    -- During combat visibility CVars are best-effort, as with the built-in
    -- nameplate keybind. Protected writes may fail; the regen edge retries.
    for name, value in pairs(desired) do Write(name, value) end
    for name in pairs(owned) do
        if desired[name] == nil then
            local fallback
            if name == "nameplateShowAll" then fallback = "1" end
            if name == "nameplateShowEnemyPets" then fallback = p.showEnemyPets == true and "1" or "0" end
            if name == "nameplateShowOnlyNameForFriendlyPlayerUnits" then
                fallback = p.friendlyNameOnly ~= false and "1" or "0"
            end
            Restore(name, fallback)
        end
    end
    -- Reapply EUI's manual OOC rule when Auto no longer owns enemies.
    if not ns.AutoNameplatesOwnsEnemy() and ns.ApplyOOCPlates then ns.ApplyOOCPlates() end

    local stacking = Value("stacking", "enabled")
    if stacking and Enum and Enum.NamePlateStackType then
        if not stackingOwned then
            stackingOwned = true
            -- The original value is the EUI manual toggle, not a captured
            -- temporary auto-setting from the previous environment.
        end
        local bit = Enum.NamePlateStackType.Enemy
        pcall(EllesmereUI.SetCVarBitfield, "nameplateStackingTypes", bit,
            Value("stacking", area), "EllesmereUINameplates")
    elseif stackingOwned then
        stackingOwned = nil
        if ns.RefreshStackingMotion then ns.RefreshStackingMotion() end
    end
end

local ctl = CreateFrame("Frame")
ctl:RegisterEvent("PLAYER_LOGIN")
ctl:RegisterEvent("PLAYER_ENTERING_WORLD")
ctl:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ctl:RegisterEvent("PLAYER_UPDATE_RESTING")
ctl:RegisterEvent("PLAYER_REGEN_DISABLED")
ctl:RegisterEvent("PLAYER_REGEN_ENABLED")
ctl:RegisterEvent("GROUP_ROSTER_UPDATE")
ctl:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then self:UnregisterEvent("PLAYER_LOGIN") end
    ns.ApplyAutoNameplates()
end)

I.broken = false
