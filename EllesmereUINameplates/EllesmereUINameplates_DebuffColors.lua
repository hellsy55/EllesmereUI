if EUI_CLIENT_BLOCKED then return end
local _, ns = ...

-- EUI_DEBUFF_COLORS: declarative aura slots own visibility. Never read aura
-- payloads, inspect secure button visibility, or infer debuffs from casts.
local rigs = {} -- [pooled EUI plate] = rig; reused when its unit changes
local config
local worker
local generation = 0
local pendingRefresh = false
local WHITE = "Interface\\Buttons\\WHITE8x8"
local STYLE = "np:debuffColorPresence"

-- Spell IDs identify DEBUFFS (Rake's damage spell, for example, is 1822).
-- Curated for debuffs players maintain on individual enemies. Names and icons
-- come from the client; verified icon paths cover unavailable spell metadata.
ns.DebuffColorPresets = {
    { 703, "Garrote", "Rogue", "Interface\\Icons\\ability_rogue_garrote" },
    { 1943, "Rupture", "Rogue", "Interface\\Icons\\ability_rogue_rupture" },
    { 1079, "Rip", "Druid", "Interface\\Icons\\ability_ghoulfrenzy" },
    { 155722, "Rake", "Druid", "Interface\\Icons\\ability_druid_disembowel" },
    { 164812, "Moonfire", "Druid", "Interface\\Icons\\spell_nature_starfall" },
    { 164815, "Sunfire", "Druid", "Interface\\Icons\\ability_mage_firestarter" },
    { 589, "Shadow Word: Pain", "Priest", "Interface\\Icons\\spell_shadow_shadowwordpain" },
    { 34914, "Vampiric Touch", "Priest", "Interface\\Icons\\spell_holy_stoicism" },
    { 980, "Agony", "Warlock", "Interface\\Icons\\spell_shadow_curseofsargeras" },
    { 146739, "Corruption", "Warlock", "Interface\\Icons\\spell_shadow_abominationexplosion" },
    { 1259790, "Unstable Affliction", "Warlock", "Interface\\Icons\\spell_shadow_unstableaffliction_3" },
    { 445474, "Wither", "Warlock", "Interface\\Icons\\inv_ability_hellcallerwarlock_wither" },
    { 188389, "Flame Shock", "Shaman", "Interface\\Icons\\spell_fire_flameshock" },
}
ns.DebuffColorPresetByID = {}
for _, spell in ipairs(ns.DebuffColorPresets) do ns.DebuffColorPresetByID[spell[1]] = spell end

local function Value(key)
    local p = ns.NP_GetProfile()
    if p and p[key] ~= nil then return p[key] end
    return ns.defaults[key]
end

-------------------------------------------------------------------------------
-- The debuff lists: one setting per class ("debuffColors" .. class token)
-- holding its single debuffs, then its combos, each list in priority order
-- (the higher entry wins), as one string so a profile copy or a per-spec
-- override carries a class's whole list as one value:
--   "spellID:r,g,b;spellID:r,g,b/spellID+spellID:r,g,b"
-- Spell 0 is a debuff not chosen yet; a combo needs two to four spells. The
-- options page edits the lists through this kit; the plates read only the
-- player's own class.
-------------------------------------------------------------------------------
local DC = {
    MAX_SINGLES = 10, MAX_COMBOS = 5, MAX_COMBO_SPELLS = 4,
    SINGLE_COLOR = { r = 1.00, g = 0.43, b = 0.04 },
    COMBO_COLOR = { r = 0.10, g = 0.88, b = 0.32 },
}
ns.DebuffColorKit = DC

function DC.Key(class) return "debuffColors" .. class end

function DC.SpellID(v)
    local id = tonumber(v)
    if id and id > 0 and id == math.floor(id) then return id end
end

local function ParseColor(s, d)
    local r, g, b = s:match("^([%d%.]+),([%d%.]+),([%d%.]+)$")
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if not (r and g and b) then return { r = d.r, g = d.g, b = d.b } end
    return { r = math.min(r, 1), g = math.min(g, 1), b = math.min(b, 1) }
end

local function Num(v) return (string.format("%.4f", v):gsub("%.?0+$", "")) end
local function ColorText(c) return Num(c.r) .. "," .. Num(c.g) .. "," .. Num(c.b) end

-- A saved list as fresh tables: singles = { { spell, color } },
-- combos = { { spells = { ids }, color } }.
function DC.Parse(s)
    local singles, combos = {}, {}
    if type(s) ~= "string" then return singles, combos end
    local singlePart, comboPart = s:match("^([^/]*)/?(.*)$")
    for entry in singlePart:gmatch("[^;]+") do
        if #singles == DC.MAX_SINGLES then break end
        local id, color = entry:match("^(%d*):?(.*)$")
        singles[#singles + 1] = { spell = DC.SpellID(id) or 0, color = ParseColor(color, DC.SINGLE_COLOR) }
    end
    for entry in comboPart:gmatch("[^;]+") do
        if #combos == DC.MAX_COMBOS then break end
        local ids, color = entry:match("^([%d%+]*):?(.*)$")
        local spells = {}
        for id in ids:gmatch("%d+") do
            id = DC.SpellID(id)
            if id and #spells < DC.MAX_COMBO_SPELLS then spells[#spells + 1] = id end
        end
        combos[#combos + 1] = { spells = spells, color = ParseColor(color, DC.COMBO_COLOR) }
    end
    return singles, combos
end

-- The string to save (nil once both lists are empty).
function DC.Encode(singles, combos)
    if #singles == 0 and #combos == 0 then return nil end
    local s, c = {}, {}
    for i, e in ipairs(singles) do s[i] = e.spell .. ":" .. ColorText(e.color) end
    for i, e in ipairs(combos) do c[i] = table.concat(e.spells, "+") .. ":" .. ColorText(e.color) end
    return table.concat(s, ";") .. "/" .. table.concat(c, ";")
end

-- A class's lists; get reads the caller's profile (the plates' by default).
function DC.Read(class, get)
    return DC.Parse((get or Value)(DC.Key(class)))
end

local function Distinct(spells)
    local out, seen = {}, {}
    for _, id in ipairs(spells) do
        if not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end

local function ReadConfig()
    local _, class = UnitClass("player")
    local singles, combos = DC.Read(class or "")
    local playerOnly = Value("debuffColorsPlayerOnly") ~= false
    local c = {
        enabled = Value("debuffColorsEnabled") == true,
        filterTokens = playerOnly and { "HARMFUL", "PLAYER" } or { "HARMFUL" },
        texture = EllesmereUI.ResolveTexturePath(ns.healthBarTextures,
            Value("healthBarTexture"), WHITE),
        singles = {}, combos = {},
    }
    local parts = { tostring(c.enabled), tostring(playerOnly), tostring(c.texture) }
    -- Declared bottom to top (a later-declared slot draws on top): the single
    -- debuffs from the end of the list up, then the combos the same way, so a
    -- combo always wins over a single debuff. A spell listed again lower down
    -- can never show beneath itself, so only its highest entry gets a slot.
    local ranked, seen = {}, {}
    for _, e in ipairs(singles) do
        if e.spell > 0 and not seen[e.spell] then
            seen[e.spell] = true
            ranked[#ranked + 1] = e
        end
    end
    for i = #ranked, 1, -1 do
        local e = ranked[i]
        c.singles[#c.singles + 1] = { spell = e.spell, color = e.color, sublevel = i == 1 and 5 or 4 }
        parts[#parts + 1] = "s" .. e.spell .. ":" .. ColorText(e.color)
    end
    for i = #combos, 1, -1 do
        local spells = Distinct(combos[i].spells)
        if #spells >= 2 then
            c.combos[#c.combos + 1] = { spells = spells, color = combos[i].color }
            parts[#parts + 1] = "c" .. table.concat(spells, "+") .. ":" .. ColorText(combos[i].color)
        end
    end
    c.any = #c.singles > 0 or #c.combos > 0
    c.fingerprint = table.concat(parts, "|")
    return c
end

local function DisableRig(rig)
    rig.unit = nil
    -- The ordinary holder hides immediately, including during a deferred parse.
    rig.holder:Hide()
    for _, container in ipairs(rig.containers) do
        container:SetEnabled(false)
        container:SetUnit("none")
    end
end

-- A rig a settings change replaces can never be freed (frames are permanent);
-- releasing its containers keeps their engine slots out of AuraKit's restyle
-- registry. Refresh runs this out of combat only.
local function DropRig(rig)
    DisableRig(rig)
    for _, container in ipairs(rig.containers) do
        EllesmereUI.AuraKit.ReleaseContainer(container)
    end
end

local function BindRig(rig, unit)
    if rig.unit == unit then return end
    rig.unit = unit
    -- Binding a slot may initialize its nested container; include new links.
    local i = 1
    while i <= #rig.containers do
        local container = rig.containers[i]
        container:SetUnit(unit)
        container:SetEnabled(true)
        i = i + 1
    end
    rig.holder:Show()
end

local function Container(rig, parent)
    local c = EllesmereUI.AuraKit.CreateContainerShell(parent, {})
    c:SetEnabled(false)
    c:SetAllPoints(rig.holder)
    c:SetFrameLevel(rig.level)
    rig.containers[#rig.containers + 1] = c
    return c
end

local function TintInitializer(rig, color, sublevel)
    local initialized = setmetatable({}, { __mode = "k" })
    return function(button)
        if initialized[button] then return end
        initialized[button] = true
        -- Only creation-window decoration. Once owned by the aura engine, these
        -- regions may become forbidden; never read or repaint them on rebind.
        button:SetFrameLevel(rig.level)
        button:EnableMouse(false)
        local tint = button:CreateTexture(nil, "ARTWORK", nil, sublevel)
        tint:SetTexture(rig.config.texture)
        tint:SetVertexColor(color.r, color.g, color.b, 1)
        tint:SetPoint("TOPLEFT", rig.fill, "TOPLEFT", 0, 0)
        tint:SetPoint("BOTTOMRIGHT", rig.fill, "BOTTOMRIGHT", 0, 0)
        if rig.mask then tint:AddMaskTexture(rig.mask) end
    end
end

local function AddSlot(rig, container, key, spell, initialize)
    EllesmereUI.AuraKit.AddSlotToContainer(container, {
        key = key, filter = rig.config.filterTokens, style = STYLE,
        candidateFilters = { includeSpellIDs = { [spell] = true } },
        extraInit = initialize,
    })
end

-- A combo is a chain of slots, each link the child of the previous spell's
-- secure button: the tint on the last link renders only while EVERY
-- engine-owned button in the chain is visible.
local function AddComboLink(rig, container, key, combo, depth)
    local spell = combo.spells[depth]
    if depth == #combo.spells then
        AddSlot(rig, container, key .. "_" .. depth, spell, TintInitializer(rig, combo.color, 7))
        return
    end
    local initialized = setmetatable({}, { __mode = "k" })
    AddSlot(rig, container, key .. "_" .. depth, spell, function(button)
        if initialized[button] then return end
        initialized[button] = true
        button:SetFrameLevel(rig.level)
        button:EnableMouse(false)
        local nested = Container(rig, button)
        AddComboLink(rig, nested, key, combo, depth + 1)
        if rig.unit then
            nested:SetUnit(rig.unit)
            nested:SetEnabled(true)
        end
    end)
end

-- The tints share one frame level (the target/focus/hover patterns sit one
-- level up), so a later-declared slot draws on top: ReadConfig orders them.
local function BuildRig(plate)
    local rig = {
        config = config, generation = generation,
        fill = plate.health:GetStatusBarTexture(), mask = plate._absorbMask,
        level = plate.health:GetFrameLevel(), containers = {},
    }
    -- Tint shares the fill's frame level; EUI's text, target/focus patterns,
    -- border and absorb effects keep their own higher layers.
    rig.holder = CreateFrame("Frame", nil, plate.health)
    rig.holder:SetAllPoints(plate.health)
    rig.holder:SetFrameLevel(rig.level)
    rig.holder:EnableMouse(false)
    rig.holder:Hide()
    local root = Container(rig, rig.holder)
    for i, single in ipairs(config.singles) do
        AddSlot(rig, root, "EUI_DEBUFF_COLOR_" .. i, single.spell,
            TintInitializer(rig, single.color, single.sublevel))
    end
    for i, combo in ipairs(config.combos) do
        AddComboLink(rig, root, "EUI_DEBUFF_COMBO_" .. i, combo, 1)
    end
    rigs[plate] = rig
    return rig
end

local function Attach(plate, unit)
    local rig = rigs[plate]
    if rig and rig.generation ~= generation then
        DisableRig(rig)
        -- Drop the old engine configuration; its forbidden regions stay hidden.
        rig = nil
    end
    if not rig then rig = BuildRig(plate) end
    -- Parent level changes propagate to all descendants. Touch only the ordinary
    -- holder; a nested container inherits its secure AuraButton's restrictions.
    rig.level = plate.health:GetFrameLevel()
    rig.holder:SetFrameLevel(rig.level)
    BindRig(rig, unit)
end

local function Detach(plate)
    local rig = rigs[plate]
    if rig and rig.unit then DisableRig(rig) end
end

local function EnsureWorker()
    if worker then return worker end
    worker = CreateFrame("Frame")
    worker:Hide()
    -- PLAYER_REGEN_ENABLED, held only while a combat-deferred refresh waits.
    worker:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if pendingRefresh then ns.DebuffColors_Refresh() end
    end)
    return worker
end

function ns.DebuffColors_Refresh()
    if not config and Value("debuffColorsEnabled") ~= true then return end
    -- Profile/spec swaps can arrive in combat. Rebuilding secure decoration is
    -- deferred; the new configuration is applied on PLAYER_REGEN_ENABLED.
    if InCombatLockdown() then
        pendingRefresh = true
        EnsureWorker():RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    pendingRefresh = false
    local nextConfig = ReadConfig()
    if config and config.fingerprint == nextConfig.fingerprint then return end
    config = nextConfig
    generation = generation + 1
    -- Clear active AND currently pooled rigs so a later plate reuse cannot bind
    -- a previous profile's spells or colors.
    for plate, rig in pairs(rigs) do
        DropRig(rig)
        rigs[plate] = nil
    end
    if config.enabled and config.any then
        local AK = EllesmereUI.AuraKit
        AK.styles[STYLE] = AK.styles[STYLE] or { noRegions = true, noTooltips = true }
        ns.DebuffColors_Attach, ns.DebuffColors_Detach = Attach, Detach
        for unit, plate in pairs(ns.plates) do Attach(plate, unit) end
    else
        -- Nothing to color: no plate hooks. An enabled config stays as the
        -- applied state Apply Coloring compares against.
        ns.DebuffColors_Attach, ns.DebuffColors_Detach = nil, nil
        if not config.enabled then config = nil end
        if worker then
            worker:UnregisterEvent("PLAYER_REGEN_ENABLED")
            worker:SetScript("OnUpdate", nil)
            worker:Hide()
        end
    end
end

-- Coalesce settings writes into one next-frame refresh; never poll aura state.
function ns.DebuffColors_RequestRefresh()
    if not config and Value("debuffColorsEnabled") ~= true then return end
    local w = EnsureWorker()
    w:SetScript("OnUpdate", function(self)
        self:Hide()
        self:SetScript("OnUpdate", nil)
        ns.DebuffColors_Refresh()
    end)
    w:Show()
end

-- List edits wait for Apply Coloring (or the options window closing): true
-- while the saved settings would build different plates than the live ones.
function ns.DebuffColors_Pending()
    if Value("debuffColorsEnabled") ~= true then return false end
    return not config or ReadConfig().fingerprint ~= config.fingerprint
end
