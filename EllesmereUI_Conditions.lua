-------------------------------------------------------------------------------
--  EllesmereUI_Conditions.lua
--  Conditional Overrides engine: condition definitions, the active-group
--  resolver, event wiring, and the keybind toggle. The value/unlock override
--  integration lives in EllesmereUI_SpecOverrides.lua (it shares that file's
--  fkey helpers); this file only decides WHICH conditional group is active
--  and notifies the override system when that changes.
--
--  Resolution ladder (user-approved):
--    1. keybind  -- any group whose keybind toggle is ON (creation order
--                   breaks ties). Explicit user action outranks ambient state.
--    2. instance -- dungeon / raid / arena / battleground. Naturally mutually
--                   exclusive (the client reports one instance type). First
--                   group in creation order that checks the current type.
--    3. solo     -- not in any group. Lowest priority.
--  Exactly one conditional group is active at a time, or none.
--
--  Condition flips NEVER happen in combat: flips are recomputed fresh at
--  PLAYER_REGEN_ENABLED (re-resolve, never replay -- the zone can change
--  twice during a fight).
-------------------------------------------------------------------------------

local L = function(s) return EllesmereUI.L and EllesmereUI.L(s) or s end

-------------------------------------------------------------------------------
--  Condition definitions (ordered display list for the picker UI).
--  comingSoon entries render disabled in the picker and never match.
-------------------------------------------------------------------------------
EllesmereUI.CONDITIONS = {
    { id = "keybind",      label = "Keybind (out of combat)" },
    { id = "dungeon",      label = "Dungeon" },
    { id = "raid",         label = "Raid" },
    { id = "arena",        label = "Arena" },
    { id = "battleground", label = "Battleground" },
    { id = "solo",         label = "Solo (not in a group)" },
    { id = "druid_form",   label = "Druid Form (out of combat)", comingSoon = true },
}

local INSTANCE_COND = {
    party = "dungeon",
    raid  = "raid",
    arena = "arena",
    pvp   = "battleground",
}

-------------------------------------------------------------------------------
--  Group store: profile.condOverrideGroups (array, creation order = priority
--  order within a tier). Mirrors profile.specOverrideGroups:
--    { id, name, icon = { kind, key }, conds = { [condID] = true },
--      key = "ALT-X" | nil, keyOn = true|nil }
--  key/keyOn only meaningful when conds.keybind; keyOn persists (profile).
-------------------------------------------------------------------------------
local function GetProfileRoot()
    if not (EllesmereUIDB and EllesmereUI.GetProfilesDB) then return nil end
    local pdb = EllesmereUI.GetProfilesDB()
    local name = pdb.activeProfile or "Default"
    return pdb.profiles and pdb.profiles[name]
end

function EllesmereUI.Conditions_GetGroups(create)
    local prof = GetProfileRoot()
    if not prof then return nil end
    if not prof.condOverrideGroups then
        if not create then return nil end
        prof.condOverrideGroups = {}
    end
    return prof.condOverrideGroups
end

function EllesmereUI.Conditions_GroupById(gid)
    local groups = EllesmereUI.Conditions_GetGroups()
    if not groups then return nil end
    for _, g in ipairs(groups) do
        if g.id == gid then return g end
    end
    return nil
end

function EllesmereUI.Conditions_NewGroupId()
    local groups = EllesmereUI.Conditions_GetGroups(true)
    local maxId = 0
    for _, g in ipairs(groups or {}) do
        if type(g.id) == "number" and g.id > maxId then maxId = g.id end
    end
    return maxId + 1
end

-------------------------------------------------------------------------------
--  Resolver
-------------------------------------------------------------------------------

--- The currently-ACTIVE conditional group per the ladder, or nil.
function EllesmereUI.Conditions_ActiveGroup()
    local groups = EllesmereUI.Conditions_GetGroups()
    if not groups or #groups == 0 then return nil end
    -- Tier 1: keybind toggles (explicit user action).
    for _, g in ipairs(groups) do
        if g.conds and g.conds.keybind and g.keyOn then return g end
    end
    -- Tier 2: instance type (client reports exactly one).
    local _, instanceType = IsInInstance()
    local cond = instanceType and INSTANCE_COND[instanceType]
    if cond then
        for _, g in ipairs(groups) do
            if g.conds and g.conds[cond] then return g end
        end
        return nil  -- in an instance: solo never applies
    end
    -- Tier 3: solo.
    if not IsInGroup() then
        for _, g in ipairs(groups) do
            if g.conds and g.conds.solo then return g end
        end
    end
    return nil
end

function EllesmereUI.Conditions_ActiveGid()
    local g = EllesmereUI.Conditions_ActiveGroup()
    return g and g.id or nil
end

-------------------------------------------------------------------------------
--  Flip machinery: flag-and-recompute, never replay. The override system's
--  transition handler (SpecOverrides_CondTransition) owns the actual
--  harvest/apply work and returns false when it cannot run yet (mid spec
--  transition, editing session open) -- the next event or the spec
--  pipeline's own Conditions_Recheck tail retries with fresh state.
-------------------------------------------------------------------------------
local _appliedGid = nil        -- gid of the conditional group currently applied
local _flipPending = false
local _establish = false       -- post profile-apply: apply-only, no harvests

function EllesmereUI.Conditions_AppliedGid()
    return _appliedGid
end

--- Profile apply swapped every store wholesale: the applied pointer refers
--- to the OLD profile's groups. Reset without a transition (the incoming
--- stores already hold their own persisted state) and let the follow-up
--- Recheck ESTABLISH against the new profile: apply-only (live is the
--- incoming raw data -- harvesting it would corrupt the new store) and
--- forced even when no conditional is active (the incoming unlock stores
--- may hold layer-valued data with a reset active pointer).
function EllesmereUI.Conditions_MarkStale()
    _appliedGid = nil
    _flipPending = false
    _establish = true
end

function EllesmereUI.Conditions_Recheck()
    if InCombatLockdown() then
        _flipPending = true
        return
    end
    local g = EllesmereUI.Conditions_ActiveGroup()
    local gid = g and g.id or nil
    if gid == _appliedGid and not _establish then return end
    -- An open unlock session never survives a layout-owner change (same rule
    -- as spec changes): discard-close first, then transition.
    if EllesmereUI._unlockModeActive and EllesmereUI.ForceCloseUnlockDiscard then
        EllesmereUI.ForceCloseUnlockDiscard()
    end
    local handler = EllesmereUI.SpecOverrides_CondTransition
    if not handler then return end
    -- Consume the establish request BEFORE the handler runs: anything inside
    -- it (a nested RefreshAllAddons tail calls MarkStale) may raise a FRESH
    -- request, which must survive this call instead of being clobbered on
    -- success -- the next signal then converges values and pointer.
    local est = _establish
    _establish = false
    if handler(_appliedGid, gid, est) then
        _appliedGid = gid
    else
        -- Busy (spec transition / edit session / re-entrant refresh): keep
        -- the request and retry on the next signal.
        _establish = est or _establish
        _flipPending = true
    end
end

-------------------------------------------------------------------------------
--  Keybind toggle: pooled hidden buttons + SetOverrideBindingClick, rebuilt
--  out of combat (regen-deferred), mirroring the Action Bars visibility
--  toggle. One key per group; presses in combat are ignored (the toggle is
--  "out of combat" by definition).
-------------------------------------------------------------------------------
local _keyBtnPool = {}
local _bindCombatFrame

function EllesmereUI.Conditions_ToggleKey(gid)
    if InCombatLockdown() then return end
    local g = EllesmereUI.Conditions_GroupById(gid)
    if not g or not (g.conds and g.conds.keybind) then return end
    g.keyOn = not g.keyOn or nil
    EllesmereUI.Conditions_Recheck()
end

function EllesmereUI.Conditions_RebuildKeyBindings()
    if InCombatLockdown() then
        if not _bindCombatFrame then
            _bindCombatFrame = CreateFrame("Frame")
            _bindCombatFrame:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                EllesmereUI.Conditions_RebuildKeyBindings()
            end)
        end
        _bindCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    for _, btn in ipairs(_keyBtnPool) do
        ClearOverrideBindings(btn)
    end
    local groups = EllesmereUI.Conditions_GetGroups()
    if not groups then return end
    local i = 0
    for _, g in ipairs(groups) do
        if g.conds and g.conds.keybind and g.key and g.key ~= "" then
            i = i + 1
            local btn = _keyBtnPool[i]
            if not btn then
                btn = CreateFrame("Button", "EUICondKeyBtn" .. i, UIParent)
                btn:Hide()
                _keyBtnPool[i] = btn
            end
            local gid = g.id
            btn:SetScript("OnClick", function() EllesmereUI.Conditions_ToggleKey(gid) end)
            SetOverrideBindingClick(btn, true, g.key, btn:GetName())
        end
    end
end

-------------------------------------------------------------------------------
--  Events. GROUP_ROSTER_UPDATE drives solo; PEW/zone drive instance flips;
--  regen drains combat-deferred rechecks. Registration order matters for the
--  regen drain: this file loads after EllesmereUI_Profiles.lua, so the spec
--  pipeline's regen branch runs first and our recompute sees settled state.
-------------------------------------------------------------------------------
local evFrame = CreateFrame("Frame")
evFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
evFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
evFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
evFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
evFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if _flipPending then
            _flipPending = false
            EllesmereUI.Conditions_Recheck()
        end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- Bindings are per-profile data; re-assert after every load screen.
        EllesmereUI.Conditions_RebuildKeyBindings()
    end
    EllesmereUI.Conditions_Recheck()
end)
