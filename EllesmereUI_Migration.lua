--------------------------------------------------------------------------------
--  EllesmereUI_Migration.lua
--  Loaded via TOC after EllesmereUI_Lite.lua, before EllesmereUI_Profiles.lua.
--  Runs at ADDON_LOADED time for "EllesmereUI" (before child addons init).
--
--  All legacy migrations have been removed. The beta-exit wipe (reset
--  version 5) guarantees every user starts from a clean slate.
--------------------------------------------------------------------------------

local floor = math.floor

--- Round all width/height values in a table to whole pixels.
--- Call from each child addon's OnInitialize after its DB is loaded.
--- keys: list of field names to round (e.g. {"width", "height"})
--- tables: list of profile sub-tables to scan
function EllesmereUI.RoundSizeFields(keys, tables)
    for _, tbl in ipairs(tables) do
        if type(tbl) == "table" then
            for _, key in ipairs(keys) do
                local v = tbl[key]
                if type(v) == "number" then
                    tbl[key] = floor(v + 0.5)
                end
            end
        end
    end
end

local migrationFrame = CreateFrame("Frame")
migrationFrame:RegisterEvent("ADDON_LOADED")
migrationFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= "EllesmereUI" then return end
    self:UnregisterEvent("ADDON_LOADED")
    -- Perform the full wipe for users updating from beta builds.
    -- This runs before child addons init so they see a clean DB.
    EllesmereUI.PerformResetWipe()
    -- Stamp fresh installs early (before child addons can create DBs
    -- that would make StampResetVersion think it's an old install).
    EllesmereUI.StampResetVersion()

    ---------------------------------------------------------------------------
    --  Migration: wipe legacy friends list data across all profiles.
    --  The friends module was fully rebuilt (session 15-17). Old profile data
    --  contains stale keys (bgAlpha without bgR/G/B, no tile/icon/group
    --  settings) that conflict with the new defaults. One-time wipe replaces
    --  the friends subtable with { enabled = <previous> } so the module stays
    --  on/off as the user had it, and fresh defaults fill the rest.
    ---------------------------------------------------------------------------
    if EllesmereUIDB and EllesmereUIDB.profiles and not EllesmereUIDB._friendsWipeDone then
        for profName, profData in pairs(EllesmereUIDB.profiles) do
            if type(profData) == "table" and profData.addons then
                local basics = profData.addons.EllesmereUIBasics
                if basics and basics.friends then
                    local wasEnabled = basics.friends.enabled
                    basics.friends = { enabled = wasEnabled }
                end
            end
        end
        EllesmereUIDB._friendsWipeDone = true
    end
end)
