-- Run from the repository root with Lua 5.1+.
local spec, config, now, combat = 1, 10, 0, false
local currentText = "old"
local frames, timers, shownText = {}, {}, {}
local profile = { loadoutTextEnabled = true, loadoutTextIntervalMin = 0 }
local function widget()
    return setmetatable({}, { __index = function(self, key)
        if key == "CreateTexture" or key == "CreateFontString" then return widget end
        if key == "SetScript" then return function(_, _, fn) self.handler = fn end end
        if key == "SetText" then return function(_, text) shownText[#shownText + 1] = text end end
        if key == "GetStringWidth" then return function() return 100 end end
        return function() end
    end })
end
function CreateFrame() local f = widget(); frames[#frames + 1] = f; return f end
function UnitClass() return "Mage", "MAGE" end
function GetTime() return now end
function InCombatLockdown() return combat end
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end,
    NewTimer = function() return { Cancel = function() end } end }
EllesmereUI, SlashCmdList = {}, {}
C_AddOns = { IsAddOnLoaded = function() return true end }
local pvp = { 7 }
C_SpecializationInfo = {
    GetSpecialization = function() return spec end,
    GetSpecializationInfo = function(i) return i * 100 end,
    GetAllSelectedPvpTalentIDs = function() return pvp end,
}
C_ClassTalents = { GetActiveConfigID = function() return config end,
    GetTraitTreeForSpec = function() return 99 end }
C_Traits = { GenerateImportString = function() return currentText end,
    GetLoadoutSerializationVersion = function() return 1 end,
    GetTreeHash = function() return { 1 } end }
local function entry(id, ranks) return { selectionEntryID = id, ranksPurchased = ranks, ranksGranted = 0 } end
local builds = {
    old = { spec = 100, entries = { entry(1, 1) } },
    new = { spec = 200, entries = { entry(2, 2) } },
    equivalent = { spec = 200, entries = { entry(2, 2) } },
    different = { spec = 200, entries = { entry(2, 1) } },
}
ExportUtil = { MakeImportDataStream = function(text) assert(builds[text]); return builds[text] end }
ClassTalentImportExportMixin = {
    ReadLoadoutHeader = function(_, stream) return true, 1, stream.spec, { 1 } end,
    IsHashEmpty = function() return false end,
    HashEquals = function() return true end,
    ReadLoadoutContent = function(_, stream) return stream.entries end,
    ConvertToImportLoadoutEntryInfo = function(_, _, _, entries) return entries end,
}
local old = { name = "Shared name", text = "old" }
TalentLoadoutEx = { Option = { IsEnabledPvp = true }, MAGE = {
    { old },
    { { name = "Group" }, { name = "Shared name", text = "different" },
      { name = "Raid", text = "new", pvp1 = 7 },
      { name = "Duplicate", text = "equivalent", pvp1 = 7 },
      { name = "Invalid", text = "invalid" } },
} }
TLX = { GetLoadedData = function() return old end } -- Stale for the entire test.
local ns = { Profile = function() return profile end }
assert(loadfile("EllesmereUIQuickdraw/EllesmereUIQuickdraw_TalentLoadouts.lua"))("Quickdraw", ns)
local watcher = frames[1]
assert(ns.GetActiveTalentLoadoutName() == "Shared name")
spec, config = 2, 20
watcher.handler(nil, "PLAYER_SPECIALIZATION_CHANGED", "player")
assert(ns.GetActiveTalentLoadoutName() == nil, "Reject old-spec config during transition")
currentText = nil
assert(ns.GetActiveTalentLoadoutName() == nil, "Unavailable config must not reuse old matches")
currentText = "new"
assert(ns.GetActiveTalentLoadoutName() == "Duplicate", "Resolve without opening the panel")
assert(not ns.IsMacrotextSlotActive({ talentLoadoutName = "Shared name" }))
assert(ns.IsMacrotextSlotActive({ talentLoadoutName = "Duplicate" }))
watcher.handler(nil, "READY_CHECK")
assert(shownText[1] == "Raid" and shownText[2] == "Duplicate", "Announce all matches in saved order")
pvp = { 8 }
watcher.handler(nil, "PLAYER_PVP_TALENT_UPDATE")
assert(ns.GetActiveTalentLoadoutName() == nil, "Respect TLEx PvP matching")
TalentLoadoutEx.Option.IsEnabledPvp = false
watcher.handler(nil, "PLAYER_PVP_TALENT_UPDATE")
assert(ns.GetActiveTalentLoadoutName() == "Duplicate")
combat = true
currentText = "different"
watcher.handler(nil, "TRAIT_CONFIG_UPDATED", config)
assert(ns.GetActiveTalentLoadoutName() == "Shared name", "Read talents in combat without loading UI")
now = 1
TalentLoadoutEx.MAGE[2][2].name = "Renamed"
assert(ns.GetActiveTalentLoadoutName() == "Renamed", "Observe saved-loadout edits")
TalentLoadoutEx = nil
assert(ns.GetActiveTalentLoadoutName() == nil, "TLEx absence is harmless")
print("Quickdraw talent loadout regression checks passed")
