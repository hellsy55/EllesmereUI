"""Exercise the shipped Debuff Colors Lua module against a visibility-driven aura engine.

Engine button reads and post-initialization writes deliberately fail. Aura
changes only go through the mock engine, never through addon aura events.
By default a slot's button is born at its first matching aura; --eager
creates it at declaration instead (the live engine's batches). Either way a
tint draws above every tint whose root slot was declared before it, and a
combo (a nested chain) above every single debuff.

Run: python .tools/tests/test_nameplate_debuff_colors.py [--eager]  (needs lupa)
"""
from pathlib import Path
import sys
from lupa import lua51

ROOT = Path(__file__).resolve().parents[2]
lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.globals().EAGER = '--eager' in sys.argv
lua.execute(r'''
ns = { defaults = { debuffColorsEnabled = false, debuffColorsPlayerOnly = true,
    healthBarTexture = "custom" }, plates = {}, healthBarTextures = {} }
profile = {}
ns.db = { profile = profile }
function ns.NP_GetProfile() return profile end
function UseProfile(t) profile = t; ns.db.profile = t end
EllesmereUI = {
    IS_FOREVER = false,
    ResolveTexturePath = function(_, key) return "test-texture-" .. key end,
}
C_AddOns = { IsAddOnLoaded = function() return true end }
function UnitClass() return "Druid", "DRUID" end
combat = false
function InCombatLockdown() return combat end
function forbidden() error("addon read restricted aura state") end
C_UnitAuras = setmetatable({}, { __index = forbidden })
UnitAura, UnitDebuff, UnitGUID = forbidden, forbidden, forbidden

frames, containers, textures = {}, {}, {}
local states = {} -- engine-private visibility state, unavailable to addon
local unitAuras = {}
local methods = {}
local declared = 0
local function Mutable(self)
    assert(not states[self].locked, "write to forbidden AuraButton/texture")
end
function methods:SetFrameLevel(level) Mutable(self); states[self].level = level end
function methods:GetFrameLevel() assert(not states[self].locked); return states[self].level or 10 end
function methods:SetAllPoints(anchor) Mutable(self); states[self].anchor = anchor end
function methods:SetPoint(...) Mutable(self); table.insert(states[self].points, {...}) end
function methods:SetSize(w, h) Mutable(self); states[self].size = { w, h } end
function methods:SetAlpha(alpha) Mutable(self); states[self].alpha = alpha end
function UIState(obj) return states[obj] end
function methods:EnableMouse(value) Mutable(self); states[self].mouse = value end
function methods:SetTexture(value) Mutable(self); states[self].texture = value end
function methods:SetVertexColor(...) Mutable(self); states[self].color = {...} end
function methods:AddMaskTexture(mask) Mutable(self); states[self].mask = mask end
function methods:Hide() Mutable(self); states[self].shown = false end
function methods:Show() Mutable(self); states[self].shown = true end
function methods:IsShown() error("addon inspected engine-owned visibility") end
function methods:GetParent() error("addon inspected engine-owned parent") end
function methods:RegisterEvent(event) states[self].events[event] = true end
function methods:UnregisterEvent(event) states[self].events[event] = nil end
function methods:SetScript(event, callback) states[self].scripts[event] = callback end
function methods:SetEnabled(enabled) states[self].enabled = enabled end
function methods:SetUnit(unit) states[self].unit = unit end
function methods:GetStatusBarTexture() return states[self].fill end

local function New(kind, parent)
    local obj = setmetatable({}, { __index = methods })
    states[obj] = { kind=kind, parent=parent, shown=true, level=10,
        points={}, scripts={}, events={}, slots={} }
    frames[#frames+1] = obj
    return obj
end
function CreateFrame(kind, _, parent, template)
    if kind == "AuraContainer" then
        assert(template == "CustomAuraContainerTemplate")
    end
    local obj = New(kind, parent)
    if kind == "AuraContainer" then containers[#containers+1] = obj end
    return obj
end
function methods:CreateTexture(_, layer, _, sublevel)
    Mutable(self)
    local tex = New("Texture", self)
    states[tex].layer, states[tex].sublevel = layer, sublevel
    textures[#textures+1] = tex
    return tex
end
local function Birth(slot)
    slot.button = New("AuraButton", slot.container)
    states[slot.button].slot = slot
    slot.init(slot.button)
    states[slot.button].locked = true
    for _, tex in ipairs(textures) do
        if states[tex].parent == slot.button then states[tex].locked = true end
    end
end
function methods:AddAuraSlot(key, filter, spec)
    assert(states[self].kind == "AuraContainer")
    assert(filter == "HARMFUL|PLAYER" or filter == "HARMFUL")
    assert(spec.candidateFilters.includeSpellIDs)
    assert(not states[self].slots[key], "slot key reused within one container")
    declared = declared + 1
    local slot = { filter=filter, ids=spec.candidateFilters.includeSpellIDs,
        init=spec.initializeFrame, decl=declared, container=self }
    states[self].slots[key] = slot
    if EAGER then Birth(slot) end
end
function SlotCount(container)
    local n = 0
    for _ in pairs(states[container].slots) do n = n + 1 end
    return n
end

local function Matches(slot, unit)
    for _, aura in ipairs(unitAuras[unit] or {}) do
        if slot.ids[aura.id] and (slot.filter == "HARMFUL" or aura.mine) then return true end
    end
    return false
end
local function UpdateEngine()
    local i = 1
    while i <= #containers do
        local c = containers[i]
        local state = states[c]
        for _, slot in pairs(state.slots) do
            local active = state.enabled and Matches(slot, state.unit)
            if active and not slot.button then Birth(slot) end
            if slot.button then states[slot.button].shown = active end
        end
        i = i + 1
    end
end
function Auras(unit, auras) unitAuras[unit] = auras; UpdateEngine() end
local function Visible(obj)
    local state = states[obj]
    if not state.shown then return false end
    return not state.parent or Visible(state.parent)
end
-- Draw order: the tint whose ROOT slot was declared last is on top, and a
-- nested chain (a combo) above every root-level tint.
local function Rank(tex)
    local slot = states[states[tex].parent].slot
    local nested = false
    while states[states[slot.container].parent].slot do
        slot = states[states[slot.container].parent].slot
        nested = true
    end
    return (nested and 1000000 or 0) + slot.decl
end
function Paint(plate)
    UpdateEngine()
    local chosen, best
    for _, tex in ipairs(textures) do
        local state = states[tex]
        if state.color and Visible(tex) then
            local parent = tex
            while parent and parent ~= plate.health do parent = states[parent].parent end
            if parent then
                local rank = Rank(tex)
                if not best or rank > best then chosen, best = state, rank end
            end
        end
    end
    return chosen
end
function NewPlate(unit)
    local plate = { health=New("StatusBar"), _absorbMask={} }
    states[plate.health].fill = New("Texture", plate.health)
    states[plate.health].baseColor = { .2, .3, .4 }
    plate.unit = unit
    ns.plates[unit] = plate
    return plate
end
function AssertColor(plate, r, g, b, msg)
    local painted = Paint(plate)
    if r == nil then assert(not painted, msg or "stale debuff tint"); return end
    assert(painted, msg or "missing active tint")
    assert(painted.color[1] == r and painted.color[2] == g and painted.color[3] == b,
        (msg or "wrong tint") .. ": got " .. tostring(painted.color[1]) .. "," ..
        tostring(painted.color[2]) .. "," .. tostring(painted.color[3]))
    assert(painted.texture == "test-texture-" .. (profile.healthBarTexture or "custom"))
    assert(painted.mask == plate._absorbMask)
    assert(painted.points[1][2] == states[plate.health].fill)
    assert(painted.points[2][2] == states[plate.health].fill)
    assert(states[plate.health].baseColor[1] == .2, "mutated base health color")
end
function RunWorker()
    for _, frame in ipairs(frames) do
        if states[frame].shown and states[frame].scripts.OnUpdate then
            states[frame].scripts.OnUpdate(frame, .2)
        end
    end
end
function Regen()
    combat = false
    for _, frame in ipairs(frames) do
        if states[frame].events.PLAYER_REGEN_ENABLED then states[frame].scripts.OnEvent(frame) end
    end
end
''')
load = lua.eval('function(src) return assert(loadstring(src)) end')

# Exercise the actual shared kit's shell/slot/release wrappers and bare
# initializer. Standard icon styling is not needed for a presence-only slot.
kit = (ROOT / 'EllesmereUI_AuraKit.lua').read_text()
kit_init = 'function AK.MakeInitializer' + kit.split('function AK.MakeInitializer', 1)[1].split(
    'function AK.CreateStyledCell', 1)[0]
kit_slots = 'function AK.CreateContainerShell' + kit.split('function AK.CreateContainerShell', 1)[1].split(
    '------------------------------------------------------------------------------\n-- Item enchantments', 1)[0]
kit_release = 'function AK.ReleaseContainer' + kit.split('function AK.ReleaseContainer', 1)[1].split(
    '------------------------------------------------------------------------------', 1)[0]
lua.execute(r'''
EllesmereUI.AuraKit = {styles={}, ApplyContainerLayout=function() end}
function EllesmereUI.AuraKit.Filter(...) return table.concat({...}, "|") end
''')
load(r'''
local AK = ...
local bd, containerData, styleButtons = {}, {}, {}
local function ApplyStyleToRegions(button, style)
    assert(style.noRegions, "presence slot allocated standard icon regions")
    button:SetSize(style.width or 32, style.height or style.width or 32)
end
local function GetStyleSet(key)
    styleButtons[key] = styleButtons[key] or {}
    return styleButtons[key]
end
''' + kit_init + kit_slots + kit_release)(lua.globals().EllesmereUI.AuraKit)
load((ROOT / 'EllesmereUINameplates/EllesmereUINameplates_DebuffColors.lua').read_text())('test', lua.globals().ns)
lua.execute(r'''
local DC = ns.DebuffColorKit
local ORANGE, RED, GREEN, BLUE, PURPLE = "1,0.43,0.04", "0.8,0.2,0.1", "0.1,0.88,0.32", "0.2,0.4,1", "0.6,0.2,0.8"

-- The list codec: round trips, 4-decimal colors, tolerant parsing, caps.
local s, c = DC.Parse("703:" .. ORANGE .. ";0:1,1,1/703+1943:" .. GREEN)
assert(#s == 2 and s[1].spell == 703 and s[2].spell == 0 and s[1].color.g == .43)
assert(#c == 1 and c[1].spells[1] == 703 and c[1].spells[2] == 1943 and c[1].color.r == .1)
assert(DC.Encode(s, c) == "703:" .. ORANGE .. ";0:1,1,1/703+1943:" .. GREEN)
assert(DC.Encode({}, {}) == nil, "an empty list left a saved value")
assert(DC.Encode({ { spell = 5, color = { r = 0.43137254, g = 0, b = 1 } } }, {}) == "5:0.4314,0,1/")
s, c = DC.Parse("junk;x:1,2;703:bad/9+x:7,7")
assert(#s == 3 and s[1].spell == 0 and s[3].spell == 703 and s[3].color.r == 1 and s[3].color.g == .43)
assert(s[2].color.r == DC.SINGLE_COLOR.r, "a malformed color did not fall back")
assert(#c == 1 and #c[1].spells == 1 and c[1].color.g == .88)
s, c = DC.Parse(("1:1,1,1;"):rep(12) .. "/" .. ("1+2+3+4+5:1,1,1;"):rep(7))
assert(#s == DC.MAX_SINGLES and #c == DC.MAX_COMBOS and #c[1].spells == DC.MAX_COMBO_SPELLS)
s, c = DC.Parse(nil)
assert(#s == 0 and #c == 0)
assert(DC.Key("DRUID") == "debuffColorsDRUID")

-- Disabled: nothing built, no hooks, no worker.
assert(#frames == 0 and not ns.DebuffColors_Attach and not ns.DebuffColors_Detach)
ns.DebuffColors_Refresh()
ns.DebuffColors_RequestRefresh()
assert(#frames == 0, "disabled feature built a frame or worker")
assert(not ns.DebuffColors_Pending())
local p = NewPlate("nameplate1")

-- Enabled with nothing listed: still no plate hooks or containers.
profile.debuffColorsEnabled = true
assert(ns.DebuffColors_Pending(), "first enable is not pending")
ns.DebuffColors_Refresh()
assert(not ns.DebuffColors_Attach and #containers == 0, "empty lists hooked the plates")
assert(not ns.DebuffColors_Pending())

-- Another class's list is never read; the player's own builds after combat.
profile.debuffColorsROGUE = "589:" .. BLUE .. "/"
assert(not ns.DebuffColors_Pending(), "another class's list changed the plates")
profile.debuffColorsDRUID = "703:" .. ORANGE .. ";1943:" .. RED .. "/703+1943:" .. GREEN
assert(ns.DebuffColors_Pending())
combat = true
ns.DebuffColors_Refresh()
assert(not ns.DebuffColors_Attach and #containers == 0, "combat change was not deferred")
Regen()
assert(ns.DebuffColors_Attach and not ns.DebuffColors_Pending())
AssertColor(p, nil)

-- Secret combat aura changes: engine visibility must be sufficient on its own.
combat = true
Auras("nameplate1", {{ id=589, mine=true }})
AssertColor(p, nil, nil, nil, "another class's debuff tinted the plate")
Auras("nameplate1", {{ id=703, mine=true }})
AssertColor(p, 1, .43, .04)
Auras("nameplate1", {{ id=1943, mine=true }})
AssertColor(p, .8, .2, .1)
Auras("nameplate1", {{ id=703, mine=true }, { id=1943, mine=true }})
AssertColor(p, .1, .88, .32, "the combo did not win")
Auras("nameplate1", {{ id=1943, mine=true }})
AssertColor(p, .8, .2, .1, "the combo outlived its first spell")
Auras("nameplate1", {})
AssertColor(p, nil)
Auras("nameplate1", {{ id=703, mine=false }, { id=1943, mine=false }})
AssertColor(p, nil, nil, nil, "someone else's debuffs counted")
local before = #containers
ns.DebuffColors_Detach(p)
ns.plates.nameplate1 = nil
AssertColor(p, nil)
ns.plates.nameplate2 = p
ns.DebuffColors_Attach(p, "nameplate2")
Auras("nameplate2", {{ id=1943, mine=true }})
AssertColor(p, .8, .2, .1)
assert(#containers == before, "plate reuse rebuilt its aura containers")

-- The higher entry wins, in both cast orders; Only My Debuffs off.
combat = false
profile.debuffColorsPlayerOnly = false
profile.debuffColorsDRUID = "703:" .. ORANGE .. ";1943:" .. RED .. "/"
ns.DebuffColors_Refresh()
Auras("nameplate2", {{ id=1943, mine=false }, { id=703, mine=false }})
AssertColor(p, 1, .43, .04, "the higher debuff did not win")
before = #containers
ns.DebuffColors_Refresh()
assert(#containers == before, "unchanged config rebuilt secure decoration")
profile.debuffColorsDRUID = "1943:" .. RED .. ";703:" .. ORANGE .. "/"
ns.DebuffColors_Refresh()
combat = true
Auras("nameplate2", {{ id=703, mine=true }})
AssertColor(p, 1, .43, .04)
Auras("nameplate2", {{ id=703, mine=true }, { id=1943, mine=true }})
AssertColor(p, .8, .2, .1, "reordering did not change the winner")
Auras("nameplate2", {{ id=1943, mine=true }})
AssertColor(p, .8, .2, .1)

-- Changes made in combat apply after combat.
profile.debuffColorsDRUID = "703:" .. ORANGE .. ";1943:" .. RED .. "/"
ns.DebuffColors_Refresh()
Auras("nameplate2", {{ id=703, mine=true }, { id=1943, mine=true }})
AssertColor(p, .8, .2, .1)
Regen()
AssertColor(p, 1, .43, .04)

-- A three-debuff combo shows only while all three are up; two combos: the
-- higher wins.
combat = false
profile.debuffColorsDRUID = "703:" .. ORANGE .. ";1943:" .. RED .. ";589:" .. PURPLE ..
    "/703+1943+589:" .. GREEN .. ";703+589:" .. BLUE
ns.DebuffColors_Refresh()
combat = true
Auras("nameplate2", {{ id=703, mine=true }, { id=1943, mine=true }})
AssertColor(p, 1, .43, .04, "a partial three-debuff combo tinted the plate")
Auras("nameplate2", {{ id=703, mine=true }, { id=1943, mine=true }, { id=589, mine=true }})
AssertColor(p, .1, .88, .32, "the higher combo did not win")
Auras("nameplate2", {{ id=703, mine=true }, { id=589, mine=true }})
AssertColor(p, .2, .4, 1)
Auras("nameplate2", {{ id=1943, mine=true }, { id=589, mine=true }})
AssertColor(p, .8, .2, .1, "a combo outlived its first spell")
combat = false
profile.debuffColorsDRUID = "703:" .. ORANGE .. ";1943:" .. RED .. ";589:" .. PURPLE ..
    "/703+589:" .. BLUE .. ";703+1943+589:" .. GREEN
ns.DebuffColors_Refresh()
Auras("nameplate2", {{ id=703, mine=true }, { id=1943, mine=true }, { id=589, mine=true }})
AssertColor(p, .2, .4, 1, "reordered combos kept the old winner")

-- Unchosen debuffs, duplicates and one-spell combos never get a slot.
profile.debuffColorsDRUID = "0:1,1,1;703:" .. ORANGE .. ";703:" .. RED .. "/703+703:" .. GREEN .. ";1943:" .. BLUE
ns.DebuffColors_Refresh()
local root = containers[#containers]
assert(SlotCount(root) == 1, "an unchosen, duplicate or one-spell entry got a slot")
Auras("nameplate2", {{ id=703, mine=true }, { id=1943, mine=true }})
AssertColor(p, 1, .43, .04, "a duplicate entry drew over its higher copy")
-- Edits that cannot change the plates are not pending.
profile.debuffColorsDRUID = profile.debuffColorsDRUID .. ";0:0,0,0"
assert(not ns.DebuffColors_Pending(), "a no-op edit is pending")

-- Coalesce repeated requests into one rebuild.
before = #containers
for i = 1, 20 do
    profile.debuffColorsDRUID = "703:0.5,0.5," .. (i / 100) .. "/"
    ns.DebuffColors_RequestRefresh()
end
assert(#containers == before)
RunWorker()
AssertColor(p, .5, .5, .2)
assert(#containers == before + 1)
RunWorker()
assert(#containers == before + 1, "the worker ran again without a request")

-- Disabling in combat applies after combat and leaves nothing armed.
combat = true
profile.debuffColorsEnabled = false
ns.DebuffColors_Refresh()
AssertColor(p, .5, .5, .2)
Regen()
AssertColor(p, nil)
assert(not ns.DebuffColors_Attach and not ns.DebuffColors_Detach)
assert(not ns.DebuffColors_Pending())
for _, frame in ipairs(frames) do
    assert(not UIState(frame).events.PLAYER_REGEN_ENABLED, "disabled feature left an event registered")
    assert(not UIState(frame).scripts.OnUpdate, "disabled feature left an update callback armed")
end

-- Profile swaps refresh active AND pooled rigs, including textures.
profile.debuffColorsEnabled = true
ns.DebuffColors_Refresh()
local pooled = NewPlate("nameplate3")
ns.DebuffColors_Attach(pooled, "nameplate3")
ns.DebuffColors_Detach(pooled)
ns.plates.nameplate3 = nil
UseProfile({ debuffColorsEnabled=true, debuffColorsDRUID="1943:0.3,0.4,0.5/", healthBarTexture="other" })
ns.DebuffColors_Refresh()
Auras("nameplate2", {{ id=703, mine=true }})
AssertColor(p, nil)
Auras("nameplate2", {{ id=1943, mine=true }})
AssertColor(p, .3, .4, .5)
ns.plates.nameplate4 = pooled
ns.DebuffColors_Attach(pooled, "nameplate4")
Auras("nameplate4", {{ id=1943, mine=true }})
AssertColor(pooled, .3, .4, .5)
ns.DebuffColors_Detach(pooled)
AssertColor(pooled, nil)

-- Saved IDs stay exact: no normalization rewrites the profile.
profile.debuffColorsDRUID = "316099:0.3,0.4,0.5/"
ns.DebuffColors_Refresh()
Auras("nameplate2", {{ id=1259790, mine=true }})
AssertColor(p, nil)
Auras("nameplate2", {{ id=316099, mine=true }})
AssertColor(p, .3, .4, .5)
assert(profile.debuffColorsDRUID == "316099:0.3,0.4,0.5/", "reading rewrote the saved list")

assert(#ns.DebuffColorPresets == 13)
assert(ns.DebuffColorPresetByID[1259790][2] == "Unstable Affliction")
assert(ns.DebuffColorPresetByID[445474][2] == "Wither")
for _, id in ipairs({121411, 2818, 259491, 106830, 335467, 55078, 55095, 191587, 217200, 12654, 316099}) do
    assert(not ns.DebuffColorPresetByID[id], "unwanted or obsolete preset remains")
end
''')
print('PASS: list codec, caps, class scoping, priority by order, combos (chains of 2-4), duplicates,')
print('      ownership, combat deferral, pooling, profiles, textures, coalesced refreshes, pending state.')

# Execute the actual Colors-page builder against mocked widgets.
options = (ROOT / 'EllesmereUIOptions/Nameplates_Options/ColorsPage_Options.lua').read_text()
helper = options.split('-- EUI_DEBUFF_COLORS: the per-class debuff lists', 1)[1].split(
    '-- Mini preview bar builder', 1)[0]
lua.execute(r'''
-- A small UI object model for the widget mocks (the engine mock above is done).
local uiMethods = {}
local function UIObj(kind, parent)
    local o = setmetatable({ kind=kind, parent=parent, scripts={}, hooks={}, shown=true,
        alpha=1, points={}, children={}, mouse=true, width=170 }, { __index = uiMethods })
    if parent and parent.children then table.insert(parent.children, o) end
    return o
end
function uiMethods:SetSize(w, h) self.width, self.height = w, h end
function uiMethods:SetPoint(...) table.insert(self.points, {...}) end
function uiMethods:GetPoint(i) local pt = self.points[i or 1]; if pt then return unpack(pt) end end
function uiMethods:ClearAllPoints() self.points = {} end
function uiMethods:SetFrameLevel(l) self.level = l end
function uiMethods:GetFrameLevel() return self.level or 1 end
function uiMethods:CreateTexture() return UIObj("Texture", self) end
function uiMethods:SetTexture(t) self.texture = t end
function uiMethods:SetVertexColor(...) self.color = {...} end
function uiMethods:SetAlpha(a) self.alpha = a end
function uiMethods:EnableMouse(v) self.mouse = v end
function uiMethods:SetScript(e, f) self.scripts[e] = f; self.hooks[e] = nil end
function uiMethods:GetScript(e) return self.scripts[e] end
function uiMethods:HookScript(e, f)
    self.hooks[e] = self.hooks[e] or {}
    table.insert(self.hooks[e], f)
end
function uiMethods:Show() self.shown = true end
function uiMethods:Hide() self.shown = false end
function uiMethods:IsShown() return self.shown end
function uiMethods:IsMouseOver() return false end
function uiMethods:SetText(t) self.text = t end
function uiMethods:GetText() return self.text end
function uiMethods:GetStringWidth() return #(self.text or "") * 7 end
function uiMethods:GetWidth() return self.width end
function uiMethods:GetChildren() return unpack(self.children) end
function Fire(o, e, ...)
    if o.scripts[e] then o.scripts[e](o, ...) end
    for _, f in ipairs(o.hooks[e] or {}) do f(o, ...) end
end
function CreateFrame(kind, _, parent) return UIObj(kind, parent) end

uiRows, uiRefreshers, uiSwatches, uiCB, uiWarn, uiMenus = {}, {}, {}, {}, {}, {}
uiNotified, uiErrors, uiOnHide, uiTips = {}, {}, {}, {}
local builds = 0
local function Region(row, cfg)
    local rgn = UIObj("Frame", row)
    rgn._cfg = cfg
    rgn._label = UIObj("FontString", rgn)
    rgn._label:SetText(cfg.text)
    local ctrl = UIObj("Button", rgn)
    ctrl:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
    if cfg.type == "button" then
        ctrl:SetScript("OnClick", function() if not cfg.disabled or not cfg.disabled() then cfg.onClick() end end)
        ctrl:SetScript("OnEnter", function() end)
        ctrl:SetScript("OnLeave", function() end)
    else
        ctrl._invalidateMenu = function() rgn.invalidations = (rgn.invalidations or 0) + 1 end
        ctrl._refreshLabel = function() rgn.shownValue = cfg.getValue and cfg.getValue() end
    end
    rgn._control = ctrl
    return rgn
end
EllesmereUI.Widgets = {
    SectionHeader=function() return {}, 30 end,
    Spacer=function() return {}, 20 end,
    DualRow=function(_, _, _, left, right)
        local row = UIObj("Frame")
        row._leftRegion, row._rightRegion = Region(row, left), Region(row, right)
        uiRows[#uiRows+1] = { left, right, frame=row }
        return row, 50
    end,
    WideButton=function(_, _, text, _, onClick, width)
        local frame = UIObj("Frame")
        local btn = UIObj("Button", frame)
        btn:SetScript("OnClick", function() onClick() end)
        uiApply = { frame=frame, button=btn, text=text, width=width }
        return frame, 62
    end,
}
EllesmereUI.PanelPP = { Point=function(f, ...) f:SetPoint(...) end, Size=function(f, w, h) f:SetSize(w, h) end }
EllesmereUI.ELLESMERE_GREEN = { r=.05, g=.82, b=.62 }
function EllesmereUI.L(s) return s end
function EllesmereUI.Lf(s, ...) return (s:gsub("%%%d%$", "%%")):format(...) end
function EllesmereUI.GetClassColor() return { r=1, g=1, b=1 } end
function EllesmereUI.HexColor() return "|cffffffff" end
function EllesmereUI.BlankRowCfg() return { type="label", text="" } end
function EllesmereUI.RegisterWidgetRefresh(fn) uiRefreshers[#uiRefreshers+1] = fn end
function EllesmereUI:RegisterOnHide(fn) uiOnHide[#uiOnHide+1] = fn end
function EllesmereUI._NotifySettingWrite(rgn) uiNotified[#uiNotified+1] = rgn end
function EllesmereUI:ShowInputPopup(opts) uiPopup = opts end
function EllesmereUI.PrintError(msg) uiErrors[#uiErrors+1] = msg end
function EllesmereUI.ShowWidgetTooltip(_, text) uiTips[#uiTips+1] = text end
function EllesmereUI.HideWidgetTooltip() end
function EllesmereUI.MakeFont(parent) return UIObj("FontString", parent) end
function EllesmereUI.SectionToggleSetValue(fn) return function(v) fn(v); EllesmereUI:RefreshPage(true) end end
function EllesmereUI.BuildInlineSwatches(rgn, list)
    uiSwatches[#uiSwatches+1] = { rgn=rgn, list=list }
    rgn._lastInline = UIObj("Button", rgn)
end
function EllesmereUI.BuildVisOptsCBDropdown(rgn, w, _, items, get, set, _, _, _, _, onClosed, opts)
    local dd = UIObj("Button", rgn)
    dd.items, dd.get, dd.set, dd.opts, dd.onClosed = items, get, set, opts, onClosed
    uiCB[#uiCB+1] = dd
    return dd, function() end
end
function EllesmereUI.AttachEmptyFilterWarn(rgn, dd, text, hasContent)
    uiWarn[#uiWarn+1] = { rgn=rgn, dd=dd, text=text, hasContent=hasContent }
    return function() end
end
function EllesmereUI.BuildDropdownMenu(btn, w, order, values, get, set, lbl, style, disabled)
    local menu = UIObj("Frame")
    menu:Hide()
    uiMenus[btn] = { menu=menu, order=order, values=values, set=set, disabled=disabled }
    return menu, nil, function() end
end
function EllesmereUI.WireDropdownScripts() end
function GetNumClasses() return 4 end
local CLASSES = { { "Warrior", "WARRIOR" }, { "Rogue", "ROGUE" }, { "Druid", "DRUID" }, { "Priest", "PRIEST" } }
function GetClassInfo(i) return CLASSES[i][1], CLASSES[i][2], i end
C_Spell = {
    GetSpellName=function(id) return "Spell " .. id end,
    GetSpellTexture=function(id) return id + 100000 end,
    GetSpellInfo=function(id) if id == 155722 or id == 33333 then return { name="Known" } end end,
}
function EllesmereUI:RefreshPage(force)
    if force then
        uiRows, uiRefreshers, uiSwatches, uiCB, uiWarn = {}, {}, {}, {}, {}
        uiApply = nil
        builds = builds + 1
        BuildPage()
    else
        for _, fn in ipairs(uiRefreshers) do fn() end
    end
end
function Builds() return builds end
-- Rows: { left cfg, right cfg, frame }; cells in reading order.
function Cells()
    local out = {}
    for _, row in ipairs(uiRows) do
        out[#out+1] = { cfg=row[1], rgn=row.frame._leftRegion }
        out[#out+1] = { cfg=row[2], rgn=row.frame._rightRegion }
    end
    return out
end
function Cell(text)
    for _, c in ipairs(Cells()) do
        if c.cfg.text == text then return c end
    end
end
-- The up / down arrows a row's chrome made (children of its region).
function Arrows(rgn)
    local out = {}
    for _, child in ipairs(rgn.children) do
        if child.kind == "Button" and child.children[1] and child.children[1].texture
            and child.children[1].texture:find("eui%-arrow") then out[#out+1] = child end
    end
    return out[1], out[2]
end
''')
load('local ns = ...\n-- EUI_DEBUFF_COLORS: the per-class debuff lists' + helper)(lua.globals().ns)
lua.execute(r'''
local DC = ns.DebuffColorKit
-- The page drives the real runtime; no plates (the engine mock is done).
ns.plates = {}
function BuildPage() ns.NP_BuildDebuffColorsOptions({}, 0) end
UseProfile({ debuffColorsEnabled=false })
ns.DebuffColors_Refresh()

-- Off: only the switch row; no Apply button, no lists.
EllesmereUI:RefreshPage(true)
assert(#uiRows == 1 and uiApply == nil)
assert(uiRows[1][1].text == "Enable Debuff Coloring" and uiRows[1][2].text == "Only My Debuffs")
assert(uiRows[1][2].disabled())

-- Enabling applies at once and builds the section: Apply, then the two Add buttons.
uiRows[1][1].setValue(true)
assert(profile.debuffColorsEnabled == true and not ns.DebuffColors_Pending())
assert(uiApply and uiApply.text == "Apply Coloring" and uiApply.button.alpha == .35)
assert(#uiRows == 2 and uiRows[2][1].text == "+ Add Debuff" and uiRows[2][2].text == "+ Add Combo")
assert(not uiRows[2][1].disabled() and uiRows[2][2].disabled(), "Add Combo enabled with no debuffs")
assert(#uiOnHide == 1, "the close hook was not registered once")

-- Add Debuff opens the classes (the player's first) and adds an unchosen debuff.
local addRgn = uiRows[2].frame._leftRegion
Fire(addRgn._control, "OnClick")
local picker = uiMenus[addRgn._control]
assert(picker.menu.shown and picker.order[1] == "DRUID" and picker.order[2] == "PRIEST")
assert(picker.values.DRUID:find("Druid", 1, true) and picker.values._noLoc)
picker.set("DRUID")
assert(profile.debuffColorsDRUID == "0:1,0.43,0.04/", "Add Debuff saved " .. tostring(profile.debuffColorsDRUID))
local d1 = Cell("Druid Debuff 1")
assert(d1 and d1.cfg.getValue() == "none" and d1.cfg.values.none == "None")
assert(uiNotified[#uiNotified] == d1.rgn, "the new row did not report the write")
assert(not ns.DebuffColors_Pending(), "an unchosen debuff is pending")
assert(d1.cfg.tooltip == "Higher in the list wins when several are up.")
assert(d1.cfg.order[1] == "remove" and d1.cfg.order[2] == "custom" and d1.cfg.order[3] == "1079",
    "the class's presets do not come first")
local sw = uiSwatches[1]
assert(sw.rgn == d1.rgn and sw.list[1].disabled(), "the color is not gated on a chosen debuff")

-- Choosing a spell saves it; Apply lights, applies, and dims again.
d1.cfg.setValue("1079")
assert(profile.debuffColorsDRUID == "1079:1,0.43,0.04/")
assert(ns.DebuffColors_Pending() and uiApply.button.alpha == 1)
Fire(uiApply.button, "OnClick")
assert(not ns.DebuffColors_Pending() and uiApply.button.alpha == .35)
sw.list[1].setValue(.2, .3, .4)
assert(profile.debuffColorsDRUID == "1079:0.2,0.3,0.4/" and ns.DebuffColors_Pending())
assert(uiApply.button.alpha == 1, "a color change (no page refresh) left Apply dim")
uiOnHide[1]()
RunWorker()
assert(not ns.DebuffColors_Pending(), "closing the options left changes unapplied")

-- A second debuff, then the arrows reorder (first up / last down disabled).
Fire(Cell("+ Add Debuff").rgn._control, "OnClick")
uiMenus[Cell("+ Add Debuff").rgn._control].set("DRUID")
Cell("Druid Debuff 2").cfg.setValue("155722")
local up1, down1 = Arrows(Cell("Druid Debuff 1").rgn)
local up2, down2 = Arrows(Cell("Druid Debuff 2").rgn)
assert(up1 and down1 and up2 and down2, "missing reorder arrows")
assert(not up1.mouse and down1.mouse and up2.mouse and not down2.mouse)
assert(up1.children[1].alpha == .2 and down2.children[1].alpha == .2)
Fire(down1, "OnClick")
assert(profile.debuffColorsDRUID == "155722:1,0.43,0.04;1079:0.2,0.3,0.4/", "move down did not swap")
up2 = Arrows(Cell("Druid Debuff 2").rgn)
Fire(up2, "OnClick")
assert(profile.debuffColorsDRUID == "1079:0.2,0.3,0.4;155722:1,0.43,0.04/", "move up did not swap")

-- Custom spells: invalid IDs refused, a valid one saved and named, empty clears.
d1 = Cell("Druid Debuff 1")
d1.cfg.values.custom.action()
assert(uiPopup.allowEmpty and uiPopup.initialText == "" and uiPopup.title == "Druid Debuff 1")
uiPopup.onConfirm("garbage")
uiPopup.onConfirm("-1")
uiPopup.onConfirm("99999999")
assert(#uiErrors == 3 and profile.debuffColorsDRUID:sub(1, 5) == "1079:")
uiPopup.onConfirm(" 33333 ")
assert(profile.debuffColorsDRUID:sub(1, 6) == "33333:" and d1.cfg.getValue() == "custom")
assert(d1.cfg.values.custom.text == "Spell 33333 (Custom)", "custom label: " .. d1.cfg.values.custom.text)
assert((d1.rgn.invalidations or 0) >= 1, "the custom name left a stale menu")
d1.cfg.values.custom.action()
assert(uiPopup.initialText == "33333")
uiPopup.onConfirm("")
assert(profile.debuffColorsDRUID:sub(1, 2) == "0:" and d1.cfg.getValue() == "none")
d1.cfg.setValue("1079")

-- Add Combo pairs the class's top two debuffs; a checkbox list edits it.
local addCombo = Cell("+ Add Combo")
assert(not addCombo.cfg.disabled())
Fire(addCombo.rgn._control, "OnClick")
local comboPicker = uiMenus[addCombo.rgn._control]
assert(comboPicker.disabled("ROGUE") and not comboPicker.disabled("DRUID"),
    "Add Combo offers a class without two debuffs")
comboPicker.set("DRUID")
assert(profile.debuffColorsDRUID == "1079:0.2,0.3,0.4;155722:1,0.43,0.04/1079+155722:0.1,0.88,0.32",
    "Add Combo saved " .. profile.debuffColorsDRUID)
local k1 = Cell("Druid Combo 1")
assert(k1 and k1.cfg.getValue() == "1079+155722" and k1.cfg.tooltip:find("Combos win", 1, true))
local cb = uiCB[1]
assert(cb.opts.noAllLabel and cb.opts.notifyWrites and cb.opts.separatorFn() == " + ")
local items = cb.items()
assert(items[1].isTopAction and items[1].label == "Remove" and #items == 3)
assert(cb.get("1079") and cb.get("155722"))
assert(#uiWarn == 1 and uiWarn[1].hasContent())
cb.set("155722", false)
assert(profile.debuffColorsDRUID:find("/1079:0.1,0.88,0.32", 1, true) and not uiWarn[1].hasContent())
cb.set("155722", true)
-- Up to four spells: a fifth stays locked.
UseProfile({ debuffColorsEnabled=true,
    debuffColorsDRUID="1:1,1,1;2:1,1,1;3:1,1,1;4:1,1,1;5:1,1,1/1+2+3+4:1,1,1" })
EllesmereUI:RefreshPage(true)
cb = uiCB[1]
items = cb.items()
assert(#items == 6)
local fifth
for _, it in ipairs(items) do if it.key == "5" then fifth = it end end
assert(fifth.lockedFn() and fifth.lockedTooltip, "a fifth combo spell is not locked")
cb.set("5", true)
assert(profile.debuffColorsDRUID:find("/1+2+3+4:", 1, true), "a fifth spell was added")
-- Remove (top action) drops the combo; the debuff menu's Remove drops a debuff.
items[1].onClick()
assert(profile.debuffColorsDRUID == "1:1,1,1;2:1,1,1;3:1,1,1;4:1,1,1;5:1,1,1/")
Cell("Druid Debuff 3").cfg.values.remove.action()
assert(profile.debuffColorsDRUID == "1:1,1,1;2:1,1,1;4:1,1,1;5:1,1,1/")
assert(Cell("Druid Debuff 4") and not Cell("Druid Debuff 5"))
-- Removing the last entry clears the saved value.
for i = 4, 1, -1 do Cell("Druid Debuff " .. i).cfg.values.remove.action() end
assert(profile.debuffColorsDRUID == nil, "an emptied list left a saved value")

-- Every class is listed after the player's; ten debuffs fill a class.
local ten = ("1:1,1,1;"):rep(10)
UseProfile({ debuffColorsEnabled=true, debuffColorsDRUID=ten .. "/", debuffColorsROGUE="703:1,1,1/" })
EllesmereUI:RefreshPage(true)
local cells = Cells() -- the first two: Enable Debuff Coloring | Only My Debuffs
assert(cells[3].cfg.text == "Druid Debuff 1" and cells[13].cfg.text == "Rogue Debuff 1")
assert(cells[14].cfg.text == "+ Add Debuff" and cells[15].cfg.text == "+ Add Combo")
assert(cells[16].cfg.type == "label", "the odd last slot is not blank")
Fire(cells[14].rgn._control, "OnClick")
assert(uiMenus[cells[14].rgn._control].disabled("DRUID") and not uiMenus[cells[14].rgn._control].disabled("ROGUE"))

-- Only My Debuffs waits for Apply too.
uiRows[1][2].setValue(false)
assert(profile.debuffColorsPlayerOnly == false and ns.DebuffColors_Pending())

-- WoW Forever: its own class roster and no presets (custom IDs only).
EllesmereUI.IS_FOREVER = true
function EllesmereUI.ForeverClasses() return { "WARRIOR", "DRUID", "MAGE" } end
function EllesmereUI.ForeverClassName(token) return token:sub(1, 1) .. token:sub(2):lower() end
UseProfile({ debuffColorsEnabled=true, debuffColorsDRUID="0:1,1,1/" })
EllesmereUI:RefreshPage(true)
d1 = Cell("Druid Debuff 1")
assert(d1 and #d1.cfg.order == 2, "WoW Forever listed retail presets")
Fire(Cell("+ Add Debuff").rgn._control, "OnClick")
local fvOrder = uiMenus[Cell("+ Add Debuff").rgn._control].order
assert(#fvOrder == 3 and fvOrder[1] == "DRUID" and fvOrder[2] == "MAGE", "WoW Forever class roster")
EllesmereUI.IS_FOREVER = false

-- The search pre-build makes rows but no chrome.
local before = #uiNotified
EllesmereUI._prebuilding = true
uiSwatches, uiCB = {}, {}
EllesmereUI:RefreshPage(true)
assert(#uiSwatches == 0 and #uiCB == 0 and #uiOnHide == 1)
EllesmereUI._prebuilding = nil
''')
print('PASS: options page: gate, Apply Coloring (pending, apply, apply on close), class picker, add/remove,')
print('      reorder arrows, custom spells, combo list (2-4 spells, warn, remove), caps, prebuild.')
